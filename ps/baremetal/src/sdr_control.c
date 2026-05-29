#include "sdr_control.h"

#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#include "sdr_regs.h"

#define SDR_DEFAULT_GAIN_SHIFT 30U
#define SDR_MIN_FREQUENCY_HZ 500000ULL
#define SDR_MAX_FREQUENCY_HZ 108000000ULL

static void copy_string(char *dst, size_t dst_size, const char *src) {
    size_t i = 0;
    if (dst_size == 0U) {
        return;
    }
    if (src == 0) {
        dst[0] = '\0';
        return;
    }
    while (i + 1U < dst_size && src[i] != '\0') {
        dst[i] = src[i];
        i++;
    }
    dst[i] = '\0';
}

static size_t append_json(char *dst, size_t dst_size, const char *fmt, ...) {
    va_list args;
    int written;

    if (dst_size == 0U) {
        return 0U;
    }

    va_start(args, fmt);
    written = vsnprintf(dst, dst_size, fmt, args);
    va_end(args);

    if (written < 0) {
        dst[0] = '\0';
        return 0U;
    }
    if ((size_t)written >= dst_size) {
        return dst_size - 1U;
    }
    return (size_t)written;
}

static int json_find_number(const char *line, const char *key, int64_t *value) {
    char pattern[48];
    const char *p;
    char *end;

    snprintf(pattern, sizeof(pattern), "\"%s\"", key);
    p = strstr(line, pattern);
    if (p == 0) {
        return 0;
    }
    p = strchr(p + strlen(pattern), ':');
    if (p == 0) {
        return 0;
    }
    p++;
    while (*p == ' ' || *p == '\t') {
        p++;
    }
    *value = strtoll(p, &end, 10);
    return end != p;
}

static int json_find_bool(const char *line, const char *key, int *value) {
    char pattern[48];
    const char *p;

    snprintf(pattern, sizeof(pattern), "\"%s\"", key);
    p = strstr(line, pattern);
    if (p == 0) {
        return 0;
    }
    p = strchr(p + strlen(pattern), ':');
    if (p == 0) {
        return 0;
    }
    p++;
    while (*p == ' ' || *p == '\t') {
        p++;
    }
    if (strncmp(p, "true", 4U) == 0) {
        *value = 1;
        return 1;
    }
    if (strncmp(p, "false", 5U) == 0) {
        *value = 0;
        return 1;
    }
    return 0;
}

static int json_find_string(const char *line, const char *key, char *value, size_t value_size) {
    char pattern[48];
    const char *p;
    size_t i = 0U;

    if (value_size == 0U) {
        return 0;
    }
    value[0] = '\0';
    snprintf(pattern, sizeof(pattern), "\"%s\"", key);
    p = strstr(line, pattern);
    if (p == 0) {
        return 0;
    }
    p = strchr(p + strlen(pattern), ':');
    if (p == 0) {
        return 0;
    }
    p++;
    while (*p == ' ' || *p == '\t') {
        p++;
    }
    if (*p != '"') {
        return 0;
    }
    p++;
    while (*p != '\0' && *p != '"' && i + 1U < value_size) {
        value[i++] = *p++;
    }
    value[i] = '\0';
    return *p == '"';
}

static int json_request_id(const char *line, int *request_id) {
    int64_t value = 0;
    if (!json_find_number(line, "request_id", &value)) {
        return 0;
    }
    *request_id = (int)value;
    return 1;
}

static int json_cmd_is(const char *line, const char *cmd) {
    char value[32];
    return json_find_string(line, "cmd", value, sizeof(value)) && strcmp(value, cmd) == 0;
}

static size_t json_error(
    char *response,
    size_t response_size,
    int request_id,
    const char *code,
    const char *message) {
    return append_json(
        response,
        response_size,
        "{\"request_id\":%d,\"ok\":false,\"error\":{\"code\":\"%s\",\"message\":\"%s\"}}\n",
        request_id,
        code,
        message);
}

static int supported_rate(uint32_t rate_hz) {
    return rate_hz == 125000U || rate_hz == 250000U || rate_hz == 500000U ||
           rate_hz == 1000000U;
}

static int rough_dbfs_from_raw(uint32_t raw) {
    if (raw >= 30000U) {
        return -1;
    }
    if (raw >= 23000U) {
        return -3;
    }
    if (raw >= 16000U) {
        return -6;
    }
    if (raw >= 8000U) {
        return -12;
    }
    if (raw >= 4000U) {
        return -18;
    }
    if (raw >= 2000U) {
        return -24;
    }
    if (raw >= 1000U) {
        return -30;
    }
    if (raw >= 500U) {
        return -36;
    }
    if (raw >= 250U) {
        return -42;
    }
    if (raw > 0U) {
        return -60;
    }
    return -120;
}

void sdr_control_init(sdr_control_t *control) {
    if (control == 0) {
        return;
    }
    memset(control, 0, sizeof(*control));
    copy_string(control->peer_ip, sizeof(control->peer_ip), "192.168.10.1");
    copy_string(control->udp_peer.destination_ip, sizeof(control->udp_peer.destination_ip), "192.168.10.1");
    control->udp_peer.iq_port = 9001U;
    control->udp_peer.psd_port = 9002U;
    control->udp_peer.status_port = 9003U;
    control->rx.stream_id = 0;
    control->rx.adc_channel = 0;
    control->rx.frequency_hz = 98500000ULL;
    control->rx.iq_sample_rate_hz = 1000000U;
    control->rx.bandwidth_hz = 250000U;
    control->rx.decimation = sdr_decimation_for_rate(control->rx.iq_sample_rate_hz);
    copy_string(control->rx.mode, sizeof(control->rx.mode), "WFM");
    control->frontend.attenuator_db = 10;
    copy_string(control->frontend.lna, sizeof(control->frontend.lna), "bypass");
    copy_string(control->frontend.filter, sizeof(control->frontend.filter), "LPF_108M");
}

void sdr_control_set_peer_ip(sdr_control_t *control, const char *peer_ip) {
    if (control == 0 || peer_ip == 0 || peer_ip[0] == '\0') {
        return;
    }
    copy_string(control->peer_ip, sizeof(control->peer_ip), peer_ip);
}

static size_t cmd_hello(
    sdr_control_t *control,
    const char *line,
    int request_id,
    char *response,
    size_t response_size) {
    int64_t value = 0;
    char dest_ip[48];

    if (!json_find_number(line, "protocol_version", &value) || value != SDR_PROTOCOL_VERSION) {
        return json_error(response, response_size, request_id, "unsupported_version",
                          "protocol_version must be 1");
    }
    if (!json_find_number(line, "iq_port", &value)) {
        return json_error(response, response_size, request_id, "invalid_field", "udp.iq_port is required");
    }
    control->udp_peer.iq_port = (uint16_t)value;
    if (!json_find_number(line, "psd_port", &value)) {
        return json_error(response, response_size, request_id, "invalid_field", "udp.psd_port is required");
    }
    control->udp_peer.psd_port = (uint16_t)value;
    if (!json_find_number(line, "status_port", &value)) {
        return json_error(response, response_size, request_id, "invalid_field", "udp.status_port is required");
    }
    control->udp_peer.status_port = (uint16_t)value;

    if (json_find_string(line, "destination_ip", dest_ip, sizeof(dest_ip))) {
        copy_string(control->udp_peer.destination_ip, sizeof(control->udp_peer.destination_ip), dest_ip);
    } else {
        copy_string(control->udp_peer.destination_ip, sizeof(control->udp_peer.destination_ip), control->peer_ip);
    }

    if (sdr_hw_set_udp_peer(&control->udp_peer) != 0) {
        return json_error(response, response_size, request_id, "hardware_fault", "failed to set UDP peer");
    }

    control->hello_seen = 1;
    return append_json(
        response,
        response_size,
        "{\"request_id\":%d,\"ok\":true,\"protocol_version\":1,"
        "\"device\":{\"name\":\"AC920-ACFL3432\",\"serial\":\"ac920\",\"firmware_version\":\"baremetal-bridge-0.1.0\",\"fpga_build_id\":\"pl-v1\"},"
        "\"limits\":{\"adc_sample_rate_hz\":250000000,\"min_frequency_hz\":500000,\"max_frequency_hz\":108000000,"
        "\"max_iq_streams\":1,\"supported_iq_sample_rates_hz\":[125000,250000,500000,1000000],"
        "\"supported_sample_formats\":[\"SC16_LE\"],\"supported_psd_sources\":[],"
        "\"supported_psd_output_bins\":[],\"supported_psd_fps\":[],\"supported_psd_sample_formats\":[],"
        "\"max_psd_segments_per_frame\":0,\"max_psd_bins_per_segment\":0,\"min_psd_span_hz\":0,"
        "\"max_psd_span_hz\":0,\"max_udp_payload_bytes\":1200}}\n",
        request_id);
}

static size_t cmd_set_frontend(
    sdr_control_t *control,
    const char *line,
    int request_id,
    char *response,
    size_t response_size) {
    int64_t number = 0;
    char text[24];

    if (json_find_number(line, "attenuator_db", &number)) {
        if (!(number == 0 || number == 10 || number == 20 || number == 30)) {
            return json_error(response, response_size, request_id, "out_of_range",
                              "attenuator_db must be 0/10/20/30");
        }
        control->frontend.attenuator_db = (int)number;
    }
    if (json_find_string(line, "lna", text, sizeof(text))) {
        if (strcmp(text, "on") != 0 && strcmp(text, "bypass") != 0) {
            return json_error(response, response_size, request_id, "invalid_field",
                              "lna must be on or bypass");
        }
        copy_string(control->frontend.lna, sizeof(control->frontend.lna), text);
    }
    if (json_find_string(line, "filter", text, sizeof(text))) {
        copy_string(control->frontend.filter, sizeof(control->frontend.filter), text);
    }

    return append_json(
        response,
        response_size,
        "{\"request_id\":%d,\"ok\":true,\"applied\":{\"attenuator_db\":%d,\"lna\":\"%s\",\"filter\":\"%s\"}}\n",
        request_id,
        control->frontend.attenuator_db,
        control->frontend.lna,
        control->frontend.filter);
}

static void program_rx_registers(const sdr_rx_config_t *rx) {
    uint32_t control_word = SDR_DDC_CONTROL_ENABLE;
    if (rx->adc_channel != 0) {
        control_word |= SDR_DDC_CONTROL_ADC_CHANNEL;
    }

    sdr_hw_stop_iq_dma();
    sdr_hw_write_reg(SDR_REG_DDC0_CONTROL, 0U);
    sdr_hw_write_reg(SDR_REG_CONTROL, SDR_CONTROL_SOFT_RESET);
    sdr_hw_write_reg(SDR_REG_CLEAR_COUNTS, 1U);
    sdr_hw_write_reg(SDR_REG_DDC0_FREQ_HZ_L, (uint32_t)rx->frequency_hz);
    sdr_hw_write_reg(SDR_REG_DDC0_FREQ_HZ_H, (uint32_t)(rx->frequency_hz >> 32));
    sdr_hw_write_reg(SDR_REG_DDC0_FREQ_WORD, sdr_freq_word(rx->frequency_hz));
    sdr_hw_write_reg(SDR_REG_DDC0_IQ_RATE, rx->iq_sample_rate_hz);
    sdr_hw_write_reg(SDR_REG_DDC0_DECIM, rx->decimation);
    sdr_hw_write_reg(SDR_REG_DDC0_BANDWIDTH, rx->bandwidth_hz);
    sdr_hw_write_reg(SDR_REG_DDC0_GAIN, SDR_DEFAULT_GAIN_SHIFT);
    sdr_hw_write_reg(SDR_REG_DDC0_GAIN_DB, 0U);
    sdr_hw_write_reg(SDR_REG_CONTROL, SDR_CONTROL_CORE_ENABLE);
    sdr_hw_write_reg(SDR_REG_DDC0_CONTROL, control_word);
}

static size_t cmd_set_rx(
    sdr_control_t *control,
    const char *line,
    int request_id,
    char *response,
    size_t response_size) {
    sdr_rx_config_t next = control->rx;
    int bool_value = 0;
    int64_t number = 0;
    char text[24];

    if (json_find_bool(line, "enable", &bool_value)) {
        next.enabled = bool_value;
    } else {
        next.enabled = 1;
    }
    if (!next.enabled) {
        sdr_control_stop_all(control);
        return append_json(
            response,
            response_size,
            "{\"request_id\":%d,\"ok\":true,\"applied\":{\"stream_id\":0,\"enable\":false}}\n",
            request_id);
    }

    if (json_find_number(line, "stream_id", &number)) {
        next.stream_id = (int)number;
    }
    if (next.stream_id != 0) {
        return json_error(response, response_size, request_id, "out_of_range",
                          "Milestone 1 bridge supports stream_id 0 only");
    }
    if (json_find_number(line, "adc_channel", &number)) {
        next.adc_channel = (int)number;
    }
    if (next.adc_channel != 0 && next.adc_channel != 1) {
        return json_error(response, response_size, request_id, "out_of_range",
                          "adc_channel must be 0 or 1");
    }
    if (json_find_number(line, "frequency_hz", &number)) {
        next.frequency_hz = (uint64_t)number;
    }
    if (next.frequency_hz < SDR_MIN_FREQUENCY_HZ || next.frequency_hz > SDR_MAX_FREQUENCY_HZ) {
        return json_error(response, response_size, request_id, "out_of_range",
                          "frequency_hz must stay within 0.5-108 MHz");
    }
    if (json_find_number(line, "iq_sample_rate_hz", &number)) {
        next.iq_sample_rate_hz = (uint32_t)number;
    }
    if (!supported_rate(next.iq_sample_rate_hz)) {
        return json_error(response, response_size, request_id, "out_of_range",
                          "unsupported iq_sample_rate_hz");
    }
    if (json_find_number(line, "bandwidth_hz", &number)) {
        next.bandwidth_hz = (uint32_t)number;
    }
    if (json_find_string(line, "sample_format", text, sizeof(text)) && strcmp(text, "SC16_LE") != 0) {
        return json_error(response, response_size, request_id, "out_of_range",
                          "sample_format must be SC16_LE");
    }
    if (json_find_string(line, "mode", text, sizeof(text))) {
        copy_string(next.mode, sizeof(next.mode), text);
    }

    next.decimation = sdr_decimation_for_rate(next.iq_sample_rate_hz);
    program_rx_registers(&next);
    if (sdr_hw_start_iq_dma() != 0) {
        sdr_hw_write_reg(SDR_REG_DDC0_CONTROL, 0U);
        sdr_hw_write_reg(SDR_REG_CONTROL, 0U);
        return json_error(response, response_size, request_id, "hardware_fault",
                          "failed to start IQ DMA");
    }
    control->rx = next;
    return append_json(
        response,
        response_size,
        "{\"request_id\":%d,\"ok\":true,\"applied\":{\"stream_id\":0,\"adc_channel\":%d,"
        "\"frequency_hz\":%llu,\"mode\":\"%s\",\"iq_sample_rate_hz\":%u,\"bandwidth_hz\":%u,"
        "\"sample_format\":\"SC16_LE\",\"decimation\":%u,\"enable\":true}}\n",
        request_id,
        control->rx.adc_channel,
        (unsigned long long)control->rx.frequency_hz,
        control->rx.mode,
        control->rx.iq_sample_rate_hz,
        control->rx.bandwidth_hz,
        control->rx.decimation);
}

static size_t cmd_set_psd(
    sdr_control_t *control,
    const char *line,
    int request_id,
    char *response,
    size_t response_size) {
    int enable = 0;
    if (json_find_bool(line, "enable", &enable) && !enable) {
        control->psd_enabled = 0;
        return append_json(
            response,
            response_size,
            "{\"request_id\":%d,\"ok\":true,\"applied\":{\"psd_id\":0,\"enable\":false,\"enabled\":false}}\n",
            request_id);
    }
    return json_error(response, response_size, request_id, "invalid_command",
                      "PSD is not implemented in the Milestone 1 PS bridge");
}

void sdr_control_stop_all(sdr_control_t *control) {
    if (control == 0) {
        return;
    }
    control->rx.enabled = 0;
    control->psd_enabled = 0;
    sdr_hw_stop_iq_dma();
    sdr_hw_write_reg(SDR_REG_DDC0_CONTROL, 0U);
    sdr_hw_write_reg(SDR_REG_CONTROL, 0U);
}

size_t sdr_control_build_status_json(
    sdr_control_t *control,
    char *payload,
    size_t payload_size) {
    sdr_hw_status_t hw;
    int adc_peak_dbfs;
    int adc_rms_dbfs;

    if (control == 0) {
        return 0U;
    }

    memset(&hw, 0, sizeof(hw));
    sdr_hw_read_status(&hw);
    adc_peak_dbfs = rough_dbfs_from_raw(hw.adc_peak);
    adc_rms_dbfs = rough_dbfs_from_raw(hw.adc_rms);
    control->status_seq++;

    return append_json(
        payload,
        payload_size,
        "{\"type\":\"status\",\"protocol_version\":1,\"seq\":%u,\"device_time_ms\":%llu,"
        "\"adc_sample_rate_hz\":250000000,"
        "\"adc\":{\"channel\":%d,\"peak_dbfs\":%d,\"rms_dbfs\":%d,\"or_count\":%u,\"clip_count\":%u,"
        "\"locked\":%s,\"peak_raw\":%u,\"rms_raw\":%u},"
        "\"frontend\":{\"attenuator_db\":%d,\"lna\":\"%s\",\"filter\":\"%s\"},"
        "\"streams\":[{\"stream_id\":0,\"adc_channel\":%d,\"enabled\":%s,\"frequency_hz\":%llu,"
        "\"mode\":\"%s\",\"iq_sample_rate_hz\":%u,\"bandwidth_hz\":%u,\"sample_format\":\"SC16_LE\","
        "\"seq\":0,\"fifo_overflow_count\":%u}],"
        "\"psd\":[{\"psd_id\":0,\"enabled\":false,\"source\":\"adc0\",\"overflow_count\":0}],"
        "\"network\":{\"iq_packets_sent\":%u,\"psd_packets_sent\":0,\"status_packets_sent\":%u,"
        "\"iq_fifo_overflow_count\":%u,\"iq_forward_errors\":%u}}\n",
        control->status_seq,
        (unsigned long long)sdr_hw_millis(),
        control->rx.adc_channel,
        adc_peak_dbfs,
        adc_rms_dbfs,
        hw.or_count,
        hw.clip_count,
        (hw.adc_status & SDR_ADC_STATUS_LOCKED) ? "true" : "false",
        hw.adc_peak,
        hw.adc_rms,
        control->frontend.attenuator_db,
        control->frontend.lna,
        control->frontend.filter,
        control->rx.adc_channel,
        control->rx.enabled ? "true" : "false",
        (unsigned long long)control->rx.frequency_hz,
        control->rx.mode,
        control->rx.iq_sample_rate_hz,
        control->rx.bandwidth_hz,
        hw.ddc0_overflow,
        control->iq_packets_forwarded,
        control->status_seq,
        hw.ddc0_overflow,
        control->iq_forward_errors);
}

int sdr_control_forward_iq_packet(
    sdr_control_t *control,
    const void *packet,
    size_t length) {
    int rc;

    if (control == 0 || packet == 0) {
        return -1;
    }
    if (!control->hello_seen || !control->rx.enabled) {
        return 0;
    }
    if (length != SDR_IQ_PACKET_BYTES) {
        control->iq_forward_errors++;
        return -2;
    }
    rc = sdr_hw_udp_send_iq(packet, length);
    if (rc == 0) {
        control->iq_packets_forwarded++;
    } else {
        control->iq_forward_errors++;
    }
    return rc;
}

size_t sdr_control_handle_line(
    sdr_control_t *control,
    const char *line,
    char *response,
    size_t response_size) {
    int request_id = 0;
    size_t status_len;

    if (response_size > 0U) {
        response[0] = '\0';
    }
    if (control == 0 || line == 0 || response == 0) {
        return 0U;
    }
    if (!json_request_id(line, &request_id)) {
        return append_json(
            response,
            response_size,
            "{\"ok\":false,\"error\":{\"code\":\"invalid_field\",\"message\":\"request_id is required\"}}\n");
    }
    if (!strstr(line, "\"cmd\"")) {
        return json_error(response, response_size, request_id, "invalid_field", "cmd is required");
    }

    if (json_cmd_is(line, "hello")) {
        return cmd_hello(control, line, request_id, response, response_size);
    }
    if (json_cmd_is(line, "ping")) {
        int64_t client_time_ms = 0;
        json_find_number(line, "client_time_ms", &client_time_ms);
        return append_json(
            response,
            response_size,
            "{\"request_id\":%d,\"ok\":true,\"client_time_ms\":%lld,\"device_time_ms\":%llu}\n",
            request_id,
            (long long)client_time_ms,
            (unsigned long long)sdr_hw_millis());
    }
    if (json_cmd_is(line, "get_status")) {
        char status_json[1792];
        status_len = sdr_control_build_status_json(control, status_json, sizeof(status_json));
        if (status_len == 0U) {
            return json_error(response, response_size, request_id, "internal_error", "status build failed");
        }
        if (status_len > 0U && status_json[status_len - 1U] == '\n') {
            status_json[status_len - 1U] = '\0';
            status_len--;
        }
        return append_json(response, response_size, "{\"request_id\":%d,\"ok\":true,\"status\":%s}\n",
                           request_id, status_json);
    }
    if (json_cmd_is(line, "set_frontend")) {
        return cmd_set_frontend(control, line, request_id, response, response_size);
    }
    if (json_cmd_is(line, "set_rx")) {
        return cmd_set_rx(control, line, request_id, response, response_size);
    }
    if (json_cmd_is(line, "set_psd")) {
        return cmd_set_psd(control, line, request_id, response, response_size);
    }
    if (json_cmd_is(line, "stop_all")) {
        sdr_control_stop_all(control);
        return append_json(response, response_size, "{\"request_id\":%d,\"ok\":true}\n", request_id);
    }
    return json_error(response, response_size, request_id, "invalid_command", "unknown command");
}
