#ifndef SDR_CONTROL_H
#define SDR_CONTROL_H

#include <stddef.h>
#include <stdint.h>

#include "sdr_hw.h"

typedef struct {
    int stream_id;
    int adc_channel;
    uint64_t frequency_hz;
    uint32_t iq_sample_rate_hz;
    uint32_t bandwidth_hz;
    char mode[12];
    int enabled;
    uint32_t decimation;
} sdr_rx_config_t;

typedef struct {
    int attenuator_db;
    char lna[12];
    char filter[20];
} sdr_frontend_config_t;

typedef struct {
    char peer_ip[48];
    sdr_udp_peer_t udp_peer;
    sdr_rx_config_t rx;
    sdr_frontend_config_t frontend;
    uint32_t status_seq;
    uint32_t iq_packets_forwarded;
    uint32_t iq_forward_errors;
    uint64_t last_status_ms;
    int hello_seen;
    int psd_enabled;
} sdr_control_t;

void sdr_control_init(sdr_control_t *control);
void sdr_control_set_peer_ip(sdr_control_t *control, const char *peer_ip);

size_t sdr_control_handle_line(
    sdr_control_t *control,
    const char *line,
    char *response,
    size_t response_size);

size_t sdr_control_build_status_json(
    sdr_control_t *control,
    char *payload,
    size_t payload_size);

int sdr_control_forward_iq_packet(
    sdr_control_t *control,
    const void *packet,
    size_t length);

void sdr_control_stop_all(sdr_control_t *control);

#endif
