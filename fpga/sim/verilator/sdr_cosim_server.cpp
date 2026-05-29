#include <arpa/inet.h>
#include <algorithm>
#include <cerrno>
#include <chrono>
#include <csignal>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <fcntl.h>
#include <netinet/in.h>
#include <string>
#include <sys/select.h>
#include <sys/socket.h>
#include <thread>
#include <unistd.h>
#include <vector>

#include "Vsdr_pl_core.h"
#include "verilated.h"

namespace {

constexpr double kAdcSampleRateHz = 250000000.0;
constexpr uint32_t kIqMagic = 0x51494453u;
constexpr uint32_t kPsdMagic = 0x53504453u;
constexpr uint16_t kProtocolVersion = 1;
constexpr uint16_t kFrameIq = 1;
constexpr uint16_t kFramePsd = 2;
constexpr uint16_t kSampleSc16 = 1;
constexpr uint16_t kPsdI16DbfsQ8 = 1;
constexpr uint16_t kIqFlagDiscontinuity = 1u << 2;
constexpr uint16_t kIqFlagConfigChanged = 1u << 3;
constexpr uint16_t kPsdFlagConfigChanged = 1u << 1;

volatile std::sig_atomic_t g_stop = 0;
vluint64_t g_sim_time = 0;

double sc_time_stamp() {
    return static_cast<double>(g_sim_time);
}

void on_signal(int) {
    g_stop = 1;
}

uint64_t now_ms() {
    timespec ts{};
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return static_cast<uint64_t>(ts.tv_sec) * 1000ull + ts.tv_nsec / 1000000ull;
}

void set_nonblock(int fd) {
    const int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);
}

bool contains(const std::string &text, const char *needle) {
    return text.find(needle) != std::string::npos;
}

int64_t json_int(const std::string &line, const char *key, int64_t fallback = 0) {
    const std::string token = std::string("\"") + key + "\"";
    const size_t pos = line.find(token);
    if (pos == std::string::npos) {
        return fallback;
    }
    size_t colon = line.find(':', pos + token.size());
    if (colon == std::string::npos) {
        return fallback;
    }
    size_t start = line.find_first_of("-0123456789", colon + 1);
    if (start == std::string::npos) {
        return fallback;
    }
    char *end = nullptr;
    const long long value = std::strtoll(line.c_str() + start, &end, 10);
    return end == line.c_str() + start ? fallback : value;
}

bool json_bool(const std::string &line, const char *key, bool fallback = false) {
    const std::string token = std::string("\"") + key + "\"";
    const size_t pos = line.find(token);
    if (pos == std::string::npos) {
        return fallback;
    }
    const size_t colon = line.find(':', pos + token.size());
    if (colon == std::string::npos) {
        return fallback;
    }
    const size_t start = line.find_first_not_of(" \t\r\n", colon + 1);
    if (start == std::string::npos) {
        return fallback;
    }
    if (line.compare(start, 4, "true") == 0) {
        return true;
    }
    if (line.compare(start, 5, "false") == 0) {
        return false;
    }
    return fallback;
}

std::string json_string(const std::string &line, const char *key, const std::string &fallback = "") {
    const std::string token = std::string("\"") + key + "\"";
    const size_t pos = line.find(token);
    if (pos == std::string::npos) {
        return fallback;
    }
    const size_t colon = line.find(':', pos + token.size());
    if (colon == std::string::npos) {
        return fallback;
    }
    const size_t first_quote = line.find('"', colon + 1);
    if (first_quote == std::string::npos) {
        return fallback;
    }
    const size_t second_quote = line.find('"', first_quote + 1);
    if (second_quote == std::string::npos) {
        return fallback;
    }
    return line.substr(first_quote + 1, second_quote - first_quote - 1);
}

void append_u16(std::vector<uint8_t> &out, uint16_t value) {
    out.push_back(static_cast<uint8_t>(value & 0xffu));
    out.push_back(static_cast<uint8_t>((value >> 8) & 0xffu));
}

void append_i16(std::vector<uint8_t> &out, int16_t value) {
    append_u16(out, static_cast<uint16_t>(value));
}

void append_u32(std::vector<uint8_t> &out, uint32_t value) {
    for (int i = 0; i < 4; ++i) {
        out.push_back(static_cast<uint8_t>((value >> (8 * i)) & 0xffu));
    }
}

void append_u64(std::vector<uint8_t> &out, uint64_t value) {
    for (int i = 0; i < 8; ++i) {
        out.push_back(static_cast<uint8_t>((value >> (8 * i)) & 0xffu));
    }
}

void append_axis_word(std::vector<uint8_t> &out, uint32_t word) {
    append_u32(out, word);
}

uint16_t decimation_for_rate(uint32_t rate) {
    if (rate == 125000) {
        return 2000;
    }
    if (rate == 250000) {
        return 1000;
    }
    if (rate == 500000) {
        return 500;
    }
    return 250;
}

uint32_t freq_word_for_hz(uint64_t frequency_hz) {
    const double scaled = static_cast<double>(frequency_hz) / kAdcSampleRateHz * 4294967296.0;
    return static_cast<uint32_t>(std::llround(scaled));
}

std::string ok_prefix(int request_id) {
    return "{\"request_id\":" + std::to_string(request_id) + ",\"ok\":true";
}

std::string error_response(int request_id, const char *code, const char *message) {
    return "{\"request_id\":" + std::to_string(request_id)
        + ",\"ok\":false,\"error\":{\"code\":\"" + code
        + "\",\"message\":\"" + message + "\"}}\n";
}

struct StreamConfig {
    bool enabled = false;
    int stream_id = 0;
    int adc_channel = 0;
    uint64_t frequency_hz = 98500000;
    std::string mode = "WFM";
    uint32_t iq_sample_rate_hz = 1000000;
    uint32_t bandwidth_hz = 250000;
    uint16_t decimation = 250;
};

struct PsdConfig {
    bool enabled = false;
    uint32_t frame_seq = 0;
    uint32_t start_frequency_hz = 500000;
    uint32_t stop_frequency_hz = 108000000;
    uint16_t fft_size = 16384;
    uint16_t output_bins = 4096;
    uint16_t fps = 10;
    bool first_frame = true;
};

struct Endpoint {
    bool valid = false;
    sockaddr_in addr{};
};

class CosimServer {
public:
    explicit CosimServer(int control_port, const std::string &bind_host)
        : control_port_(control_port), bind_host_(bind_host) {}

    ~CosimServer() {
        close_fd(client_fd_);
        close_fd(listen_fd_);
        close_fd(udp_fd_);
    }

    bool init() {
        signal(SIGINT, on_signal);
        signal(SIGTERM, on_signal);

        listen_fd_ = socket(AF_INET, SOCK_STREAM, 0);
        udp_fd_ = socket(AF_INET, SOCK_DGRAM, 0);
        if (listen_fd_ < 0 || udp_fd_ < 0) {
            perror("socket");
            return false;
        }
        int one = 1;
        setsockopt(listen_fd_, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
        set_nonblock(listen_fd_);

        sockaddr_in addr{};
        addr.sin_family = AF_INET;
        addr.sin_port = htons(static_cast<uint16_t>(control_port_));
        if (inet_aton(bind_host_.c_str(), &addr.sin_addr) == 0) {
            fprintf(stderr, "invalid bind address: %s\n", bind_host_.c_str());
            return false;
        }
        if (bind(listen_fd_, reinterpret_cast<sockaddr *>(&addr), sizeof(addr)) < 0) {
            perror("bind");
            return false;
        }
        if (listen(listen_fd_, 1) < 0) {
            perror("listen");
            return false;
        }

        dut_.rst = 1;
        dut_.clear_status_counts = 0;
        dut_.adc_offset_binary = 0;
        dut_.adc_ch0_sample_14 = 0;
        dut_.adc_ch1_sample_14 = 0;
        dut_.adc_sample_valid = 0;
        dut_.adc_or = 0;
        dut_.adc_locked = 0;
        dut_.core_enable = 0;
        dut_.ddc0_enable = 0;
        dut_.ddc0_adc_channel = 0;
        dut_.ddc0_config_changed = 0;
        dut_.ddc0_freq_word = 0;
        dut_.ddc0_decim_rate = 250;
        dut_.ddc0_gain_shift = 30;
        dut_.ddc0_frequency_hz = 98500000;
        dut_.ddc0_iq_sample_rate_hz = 1000000;
        dut_.ddc0_bandwidth_hz = 250000;
        dut_.ddc0_gain_db_q8 = 0;
        dut_.m_axis_iq_tready = 1;
        for (int i = 0; i < 16; ++i) {
            step_rtl();
        }
        dut_.rst = 0;
        boot_ms_ = now_ms();
        next_status_ms_ = boot_ms_ + 200;
        next_psd_ms_ = boot_ms_ + 250;
        printf("Verilated AC920 cosim listening on %s:%d\n", bind_host_.c_str(), control_port_);
        fflush(stdout);
        return true;
    }

    void run() {
        while (!g_stop) {
            poll_network();
            const int cycles = stream_.enabled ? 10000 : 2000;
            for (int i = 0; i < cycles; ++i) {
                step_rtl();
            }
            const uint64_t now = now_ms();
            if (status_dest_.valid && now >= next_status_ms_) {
                send_status();
                next_status_ms_ = now + (stream_.enabled || psd_.enabled ? 250 : 1000);
            }
            if (psd_dest_.valid && psd_.enabled && now >= next_psd_ms_) {
                send_psd_frame();
                next_psd_ms_ = now + 1000 / std::max<uint16_t>(psd_.fps, 1);
            }
            std::this_thread::sleep_for(std::chrono::microseconds(stream_.enabled ? 1000 : 1000));
        }
    }

private:
    static void close_fd(int &fd) {
        if (fd >= 0) {
            close(fd);
            fd = -1;
        }
    }

    void step_rtl() {
        if (config_changed_pulses_ > 0) {
            dut_.ddc0_config_changed = 1;
            config_changed_pulses_--;
        } else {
            dut_.ddc0_config_changed = 0;
        }

        const double tone_hz = static_cast<double>(stream_.frequency_hz) + 1000.0;
        rf_phase_ += 2.0 * M_PI * tone_hz / kAdcSampleRateHz;
        if (rf_phase_ > 2.0 * M_PI) {
            rf_phase_ -= 2.0 * M_PI;
        }
        const int sample = static_cast<int>(std::lrint(4096.0 * std::sin(rf_phase_)));
        const uint16_t sample14 = static_cast<uint16_t>(sample) & 0x3fffu;
        dut_.adc_ch0_sample_14 = sample14;
        dut_.adc_ch1_sample_14 = sample14;
        dut_.adc_sample_valid = 1;
        dut_.adc_locked = 1;
        dut_.m_axis_iq_tready = 1;

        dut_.clk = 0;
        dut_.eval();
        g_sim_time++;
        dut_.clk = 1;
        dut_.eval();
        g_sim_time++;

        if (!dut_.rst && dut_.m_axis_iq_tvalid && dut_.m_axis_iq_tready) {
            append_axis_word(iq_packet_, dut_.m_axis_iq_tdata);
            if (dut_.m_axis_iq_tlast) {
                if (iq_dest_.valid && iq_packet_.size() >= 64) {
                    sendto(
                        udp_fd_,
                        iq_packet_.data(),
                        iq_packet_.size(),
                        0,
                        reinterpret_cast<sockaddr *>(&iq_dest_.addr),
                        sizeof(iq_dest_.addr)
                    );
                    iq_packets_sent_++;
                }
                iq_packet_.clear();
            }
        }
    }

    void poll_network() {
        fd_set rfds;
        FD_ZERO(&rfds);
        FD_SET(listen_fd_, &rfds);
        int max_fd = listen_fd_;
        if (client_fd_ >= 0) {
            FD_SET(client_fd_, &rfds);
            max_fd = std::max(max_fd, client_fd_);
        }
        timeval tv{};
        tv.tv_sec = 0;
        tv.tv_usec = 0;
        const int ready = select(max_fd + 1, &rfds, nullptr, nullptr, &tv);
        if (ready <= 0) {
            return;
        }
        if (FD_ISSET(listen_fd_, &rfds)) {
            accept_client();
        }
        if (client_fd_ >= 0 && FD_ISSET(client_fd_, &rfds)) {
            read_client();
        }
    }

    void accept_client() {
        sockaddr_in peer{};
        socklen_t len = sizeof(peer);
        const int fd = accept(listen_fd_, reinterpret_cast<sockaddr *>(&peer), &len);
        if (fd < 0) {
            return;
        }
        if (client_fd_ >= 0) {
            const std::string busy = "{\"ok\":false,\"error\":{\"code\":\"busy\","
                "\"message\":\"device already has an owner\"}}\n";
            send(fd, busy.data(), busy.size(), 0);
            close(fd);
            return;
        }
        client_fd_ = fd;
        set_nonblock(client_fd_);
        client_ip_ = inet_ntoa(peer.sin_addr);
        rx_buffer_.clear();
        printf("control client connected from %s\n", client_ip_.c_str());
        fflush(stdout);
    }

    void read_client() {
        char buf[4096];
        while (true) {
            const ssize_t n = recv(client_fd_, buf, sizeof(buf), 0);
            if (n > 0) {
                rx_buffer_.append(buf, static_cast<size_t>(n));
                process_lines();
                continue;
            }
            if (n == 0) {
                close_control();
                return;
            }
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                return;
            }
            close_control();
            return;
        }
    }

    void close_control() {
        close_fd(client_fd_);
        rx_buffer_.clear();
        stream_.enabled = false;
        psd_.enabled = false;
        iq_dest_.valid = false;
        psd_dest_.valid = false;
        status_dest_.valid = false;
        apply_stream_config(false);
        printf("control client disconnected\n");
        fflush(stdout);
    }

    void process_lines() {
        while (true) {
            const size_t pos = rx_buffer_.find('\n');
            if (pos == std::string::npos) {
                return;
            }
            const std::string line = rx_buffer_.substr(0, pos);
            rx_buffer_.erase(0, pos + 1);
            handle_request(line);
        }
    }

    void send_line(const std::string &line) {
        if (client_fd_ >= 0) {
            send(client_fd_, line.data(), line.size(), 0);
        }
    }

    void handle_request(const std::string &line) {
        const int request_id = static_cast<int>(json_int(line, "request_id", 0));
        const std::string cmd = json_string(line, "cmd");
        if (request_id == 0 || cmd.empty()) {
            send_line(error_response(request_id, "invalid_field", "request_id and cmd are required"));
            return;
        }
        if (cmd == "hello") {
            handle_hello(line, request_id);
        } else if (cmd == "ping") {
            send_line(ok_prefix(request_id) + ",\"client_time_ms\":"
                + std::to_string(json_int(line, "client_time_ms", 0))
                + ",\"device_time_ms\":" + std::to_string(device_time_ms()) + "}\n");
        } else if (cmd == "get_status") {
            send_line(ok_prefix(request_id) + ",\"status\":" + status_json() + "}\n");
        } else if (cmd == "set_frontend") {
            send_line(ok_prefix(request_id)
                + ",\"applied\":{\"attenuator_db\":10,\"lna\":\"bypass\","
                "\"filter\":\"LPF_108M\"}}\n");
        } else if (cmd == "set_rx") {
            handle_set_rx(line, request_id);
        } else if (cmd == "set_psd") {
            handle_set_psd(line, request_id);
        } else if (cmd == "stop_all") {
            stream_.enabled = false;
            psd_.enabled = false;
            apply_stream_config(false);
            send_line(ok_prefix(request_id) + "}\n");
        } else {
            send_line(error_response(request_id, "invalid_command", "unknown command"));
        }
    }

    void handle_hello(const std::string &line, int request_id) {
        const std::string dest_ip = json_string(line, "destination_ip", client_ip_);
        iq_dest_ = make_dest(dest_ip, static_cast<uint16_t>(json_int(line, "iq_port", 9001)));
        psd_dest_ = make_dest(dest_ip, static_cast<uint16_t>(json_int(line, "psd_port", 9002)));
        status_dest_ = make_dest(dest_ip, static_cast<uint16_t>(json_int(line, "status_port", 9003)));
        send_line(ok_prefix(request_id)
            + ",\"protocol_version\":1,"
            "\"device\":{\"name\":\"verilated-AC920-PL\",\"serial\":\"cosim\","
            "\"firmware_version\":\"cosim\",\"fpga_build_id\":\"verilator\"},"
            "\"limits\":{\"adc_sample_rate_hz\":250000000,"
            "\"min_frequency_hz\":500000,\"max_frequency_hz\":108000000,"
            "\"max_iq_streams\":1,"
            "\"supported_iq_sample_rates_hz\":[125000,250000,500000,1000000],"
            "\"supported_sample_formats\":[\"SC16_LE\"],"
            "\"supported_psd_sources\":[\"adc0\"],"
            "\"supported_psd_output_bins\":[4096],"
            "\"supported_psd_fps\":[10],"
            "\"supported_psd_sample_formats\":[\"I16_DBFS_Q8\"],"
            "\"max_psd_segments_per_frame\":8,"
            "\"max_psd_bins_per_segment\":512,"
            "\"min_psd_span_hz\":100000,"
            "\"max_psd_span_hz\":107500000,"
            "\"max_udp_payload_bytes\":1200}}\n");
    }

    void handle_set_rx(const std::string &line, int request_id) {
        const bool enable = json_bool(line, "enable", stream_.enabled);
        if (!enable) {
            stream_.enabled = false;
            apply_stream_config(false);
            send_line(ok_prefix(request_id) + ",\"applied\":{\"stream_id\":0,\"enable\":false}}\n");
            return;
        }
        stream_.stream_id = static_cast<int>(json_int(line, "stream_id", 0));
        stream_.adc_channel = static_cast<int>(json_int(line, "adc_channel", 0));
        stream_.frequency_hz = static_cast<uint64_t>(json_int(line, "frequency_hz", 98500000));
        stream_.mode = json_string(line, "mode", "WFM");
        stream_.iq_sample_rate_hz = static_cast<uint32_t>(
            json_int(line, "iq_sample_rate_hz", 1000000));
        stream_.bandwidth_hz = static_cast<uint32_t>(json_int(line, "bandwidth_hz", 250000));
        stream_.decimation = decimation_for_rate(stream_.iq_sample_rate_hz);
        stream_.enabled = true;
        apply_stream_config(true);
        send_line(ok_prefix(request_id)
            + ",\"applied\":{\"stream_id\":0,\"adc_channel\":"
            + std::to_string(stream_.adc_channel)
            + ",\"frequency_hz\":" + std::to_string(stream_.frequency_hz)
            + ",\"mode\":\"" + stream_.mode
            + "\",\"iq_sample_rate_hz\":" + std::to_string(stream_.iq_sample_rate_hz)
            + ",\"bandwidth_hz\":" + std::to_string(stream_.bandwidth_hz)
            + ",\"sample_format\":\"SC16_LE\",\"decimation\":"
            + std::to_string(stream_.decimation)
            + ",\"enable\":true}}\n");
    }

    void handle_set_psd(const std::string &line, int request_id) {
        psd_.enabled = json_bool(line, "enable", true);
        psd_.start_frequency_hz = static_cast<uint32_t>(
            json_int(line, "start_frequency_hz", psd_.start_frequency_hz));
        psd_.stop_frequency_hz = static_cast<uint32_t>(
            json_int(line, "stop_frequency_hz", psd_.stop_frequency_hz));
        psd_.fft_size = static_cast<uint16_t>(json_int(line, "fft_size", 16384));
        psd_.output_bins = static_cast<uint16_t>(json_int(line, "output_bins", 4096));
        psd_.fps = static_cast<uint16_t>(json_int(line, "fps", 10));
        psd_.first_frame = true;
        send_line(ok_prefix(request_id)
            + ",\"applied\":{\"psd_id\":0,\"source\":\"adc0\",\"enable\":"
            + std::string(psd_.enabled ? "true" : "false")
            + ",\"enabled\":" + std::string(psd_.enabled ? "true" : "false")
            + ",\"start_frequency_hz\":" + std::to_string(psd_.start_frequency_hz)
            + ",\"stop_frequency_hz\":" + std::to_string(psd_.stop_frequency_hz)
            + ",\"fft_size\":" + std::to_string(psd_.fft_size)
            + ",\"output_bins\":" + std::to_string(psd_.output_bins)
            + ",\"fps\":" + std::to_string(psd_.fps)
            + ",\"sample_format\":\"I16_DBFS_Q8\"}}\n");
    }

    Endpoint make_dest(const std::string &ip, uint16_t port) {
        Endpoint endpoint;
        endpoint.addr.sin_family = AF_INET;
        endpoint.addr.sin_port = htons(port);
        endpoint.valid = inet_aton(ip.c_str(), &endpoint.addr.sin_addr) != 0;
        return endpoint;
    }

    void apply_stream_config(bool enabled) {
        dut_.core_enable = enabled ? 1 : 0;
        dut_.ddc0_enable = enabled ? 1 : 0;
        dut_.ddc0_adc_channel = stream_.adc_channel & 1;
        dut_.ddc0_freq_word = freq_word_for_hz(stream_.frequency_hz);
        dut_.ddc0_decim_rate = stream_.decimation;
        dut_.ddc0_gain_shift = 30;
        dut_.ddc0_frequency_hz = stream_.frequency_hz;
        dut_.ddc0_iq_sample_rate_hz = stream_.iq_sample_rate_hz;
        dut_.ddc0_bandwidth_hz = stream_.bandwidth_hz;
        dut_.ddc0_gain_db_q8 = 0;
        config_changed_pulses_ = 3;
        iq_packet_.clear();
    }

    uint64_t device_time_ms() const {
        return now_ms() - boot_ms_;
    }

    std::string status_json() const {
        return "{\"type\":\"status\",\"protocol_version\":1,\"seq\":"
            + std::to_string(status_seq_)
            + ",\"device_time_ms\":" + std::to_string(device_time_ms())
            + ",\"adc_sample_rate_hz\":250000000,"
            "\"adc\":{\"channel\":0,\"peak_dbfs\":-12.0,"
            "\"rms_dbfs\":-28.0,\"or_count\":0,\"clip_count\":"
            + std::to_string(static_cast<uint32_t>(dut_.adc_clip_count))
            + "},\"frontend\":{\"attenuator_db\":10,\"lna\":\"bypass\","
            "\"filter\":\"LPF_108M\"},\"streams\":["
            + (stream_.enabled ? stream_status_json() : std::string(""))
            + "],\"psd\":[{\"psd_id\":0,\"enabled\":"
            + std::string(psd_.enabled ? "true" : "false")
            + ",\"source\":\"adc0\",\"start_frequency_hz\":"
            + std::to_string(psd_.start_frequency_hz)
            + ",\"stop_frequency_hz\":" + std::to_string(psd_.stop_frequency_hz)
            + ",\"fft_size\":" + std::to_string(psd_.fft_size)
            + ",\"output_bins\":" + std::to_string(psd_.output_bins)
            + ",\"fps\":" + std::to_string(psd_.fps)
            + ",\"frame_seq\":" + std::to_string(psd_.frame_seq)
            + ",\"dropped_frame_count\":0,\"missing_segment_count\":0,"
            "\"overflow_count\":0}],\"network\":{\"iq_packets_sent\":"
            + std::to_string(iq_packets_sent_)
            + ",\"psd_packets_sent\":" + std::to_string(psd_packets_sent_)
            + ",\"status_packets_sent\":" + std::to_string(status_seq_)
            + ",\"iq_fifo_overflow_count\":"
            + std::to_string(static_cast<uint32_t>(dut_.ddc0_overflow_count))
            + ",\"psd_fifo_overflow_count\":0}}";
    }

    std::string stream_status_json() const {
        return "{\"stream_id\":0,\"adc_channel\":" + std::to_string(stream_.adc_channel)
            + ",\"enabled\":true,\"frequency_hz\":" + std::to_string(stream_.frequency_hz)
            + ",\"mode\":\"" + stream_.mode
            + "\",\"iq_sample_rate_hz\":" + std::to_string(stream_.iq_sample_rate_hz)
            + ",\"bandwidth_hz\":" + std::to_string(stream_.bandwidth_hz)
            + ",\"sample_format\":\"SC16_LE\",\"seq\":0,\"fifo_overflow_count\":"
            + std::to_string(static_cast<uint32_t>(dut_.ddc0_overflow_count)) + "}";
    }

    void send_status() {
        status_seq_++;
        const std::string payload = status_json();
        sendto(
            udp_fd_,
            payload.data(),
            payload.size(),
            0,
            reinterpret_cast<sockaddr *>(&status_dest_.addr),
            sizeof(status_dest_.addr)
        );
    }

    void send_psd_frame() {
        const uint16_t total_bins = 4096;
        const uint16_t bins_per_segment = 512;
        const uint16_t segment_count = total_bins / bins_per_segment;
        const uint64_t span = psd_.stop_frequency_hz - psd_.start_frequency_hz;
        const uint64_t spacing_millihz = span * 1000ull / total_bins;
        const uint16_t flags = psd_.first_frame ? kPsdFlagConfigChanged : 0;
        psd_.first_frame = false;

        for (uint16_t seg = 0; seg < segment_count; ++seg) {
            std::vector<uint8_t> packet;
            packet.reserve(1096);
            append_u32(packet, kPsdMagic);
            append_u16(packet, kProtocolVersion);
            append_u16(packet, 72);
            append_u16(packet, kFramePsd);
            append_u16(packet, 0);
            append_u32(packet, psd_.frame_seq);
            append_u64(packet, device_time_ms() * 250000ull);
            append_u64(packet, psd_.start_frequency_hz);
            append_u64(packet, spacing_millihz);
            append_u32(packet, psd_.fft_size);
            append_u16(packet, total_bins);
            append_u16(packet, seg);
            append_u16(packet, segment_count);
            append_u16(packet, seg * bins_per_segment);
            append_u16(packet, bins_per_segment);
            append_u16(packet, kPsdI16DbfsQ8);
            append_u16(packet, flags);
            append_u16(packet, 4);
            append_u32(packet, bins_per_segment * 2u);
            append_u64(packet, psd_.stop_frequency_hz);
            for (uint16_t i = 0; i < bins_per_segment; ++i) {
                const uint32_t bin = seg * bins_per_segment + i;
                double db = -95.0 + 3.0 * static_cast<double>((bin * 17) % 31) / 31.0;
                const double freq = psd_.start_frequency_hz
                    + (static_cast<double>(bin) + 0.5) * static_cast<double>(span) / total_bins;
                const double carriers[] = {1000000.0, 7100000.0, 14200000.0, 98500000.0};
                for (double carrier : carriers) {
                    const double distance_bins = std::fabs(freq - carrier)
                        / (static_cast<double>(span) / total_bins);
                    if (distance_bins < 5.0) {
                        db = std::max(db, -38.0 - distance_bins * 4.5);
                    }
                }
                append_i16(packet, static_cast<int16_t>(std::lrint(db * 256.0)));
            }
            sendto(
                udp_fd_,
                packet.data(),
                packet.size(),
                0,
                reinterpret_cast<sockaddr *>(&psd_dest_.addr),
                sizeof(psd_dest_.addr)
            );
            psd_packets_sent_++;
        }
        psd_.frame_seq++;
    }

    int control_port_;
    std::string bind_host_;
    int listen_fd_ = -1;
    int client_fd_ = -1;
    int udp_fd_ = -1;
    std::string client_ip_ = "127.0.0.1";
    std::string rx_buffer_;
    Endpoint iq_dest_;
    Endpoint psd_dest_;
    Endpoint status_dest_;
    StreamConfig stream_;
    PsdConfig psd_;
    Vsdr_pl_core dut_;
    std::vector<uint8_t> iq_packet_;
    uint64_t boot_ms_ = 0;
    uint64_t next_status_ms_ = 0;
    uint64_t next_psd_ms_ = 0;
    uint32_t status_seq_ = 0;
    uint32_t iq_packets_sent_ = 0;
    uint32_t psd_packets_sent_ = 0;
    int config_changed_pulses_ = 0;
    double rf_phase_ = 0.0;
};

}  // namespace

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    int control_port = 9000;
    std::string bind_host = "127.0.0.1";
    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];
        if (arg == "--control-port" && i + 1 < argc) {
            control_port = std::atoi(argv[++i]);
        } else if (arg == "--bind" && i + 1 < argc) {
            bind_host = argv[++i];
        } else if (arg == "--help") {
            printf("usage: %s [--bind 127.0.0.1] [--control-port 9000]\n", argv[0]);
            return 0;
        }
    }

    CosimServer server(control_port, bind_host);
    if (!server.init()) {
        return 1;
    }
    server.run();
    return 0;
}
