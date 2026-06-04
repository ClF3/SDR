#ifndef SDR_HW_H
#define SDR_HW_H

#include <stddef.h>
#include <stdint.h>

typedef struct {
    char destination_ip[48];
    uint16_t iq_port;
    uint16_t psd_port;
    uint16_t status_port;
} sdr_udp_peer_t;

typedef struct {
    uint32_t core_id;
    uint32_t core_version;
    uint32_t control;
    uint32_t adc_status;
    uint32_t adc_peak;
    uint32_t adc_rms;
    uint32_t or_count;
    uint32_t clip_count;
    uint64_t adc_timestamp;
    uint32_t adc_debug_flags;
    uint32_t adc_dvalid_count;
    uint32_t adc_cfg_update_count;
    uint32_t ddc0_samples;
    uint32_t ddc0_overflow;
} sdr_hw_status_t;

int sdr_hw_init(void);
uint64_t sdr_hw_millis(void);

uint32_t sdr_hw_read_reg(uint32_t offset);
void sdr_hw_write_reg(uint32_t offset, uint32_t value);
void sdr_hw_read_status(sdr_hw_status_t *status);

int sdr_hw_start_iq_dma(void);
void sdr_hw_stop_iq_dma(void);

int sdr_hw_set_udp_peer(const sdr_udp_peer_t *peer);
int sdr_hw_udp_send_iq(const void *packet, size_t length);
int sdr_hw_udp_send_status(const void *payload, size_t length);

#endif
