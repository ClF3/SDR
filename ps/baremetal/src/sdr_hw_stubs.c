#include "sdr_hw.h"

#include "sdr_regs.h"

#if defined(__GNUC__)
#define SDR_WEAK __attribute__((weak))
#else
#define SDR_WEAK
#endif

SDR_WEAK int sdr_hw_init(void) {
    return 0;
}

SDR_WEAK uint64_t sdr_hw_millis(void) {
    return 0;
}

SDR_WEAK uint32_t sdr_hw_read_reg(uint32_t offset) {
    switch (offset) {
    case SDR_REG_CORE_ID:
        return SDR_CORE_ID_EXPECTED;
    case SDR_REG_CORE_VERSION:
        return SDR_CORE_VERSION_EXPECTED;
    case SDR_REG_ADC_STATUS:
        return SDR_ADC_STATUS_LOCKED;
    default:
        return 0;
    }
}

SDR_WEAK void sdr_hw_write_reg(uint32_t offset, uint32_t value) {
    (void)offset;
    (void)value;
}

SDR_WEAK void sdr_hw_read_status(sdr_hw_status_t *status) {
    if (status == 0) {
        return;
    }
    status->core_id = sdr_hw_read_reg(SDR_REG_CORE_ID);
    status->core_version = sdr_hw_read_reg(SDR_REG_CORE_VERSION);
    status->control = sdr_hw_read_reg(SDR_REG_CONTROL);
    status->adc_status = sdr_hw_read_reg(SDR_REG_ADC_STATUS);
    status->adc_peak = sdr_hw_read_reg(SDR_REG_ADC_PEAK);
    status->adc_rms = sdr_hw_read_reg(SDR_REG_ADC_RMS);
    status->or_count = sdr_hw_read_reg(SDR_REG_OR_COUNT);
    status->clip_count = sdr_hw_read_reg(SDR_REG_CLIP_COUNT);
    status->adc_timestamp = (uint64_t)sdr_hw_read_reg(SDR_REG_ADC_TIMESTAMP_L) |
                            ((uint64_t)sdr_hw_read_reg(SDR_REG_ADC_TIMESTAMP_H) << 32);
    status->adc_debug_flags = sdr_hw_read_reg(SDR_REG_ADC_DEBUG_FLAGS);
    status->adc_dvalid_count = sdr_hw_read_reg(SDR_REG_ADC_DVALID_COUNT);
    status->adc_cfg_update_count = sdr_hw_read_reg(SDR_REG_ADC_CFG_UPDATE_COUNT);
    status->ddc0_samples = sdr_hw_read_reg(SDR_REG_DDC0_SAMPLES);
    status->ddc0_overflow = sdr_hw_read_reg(SDR_REG_DDC0_OVERFLOW);
}

SDR_WEAK int sdr_hw_start_iq_dma(void) {
    return 0;
}

SDR_WEAK void sdr_hw_stop_iq_dma(void) {
}

SDR_WEAK int sdr_hw_set_udp_peer(const sdr_udp_peer_t *peer) {
    (void)peer;
    return 0;
}

SDR_WEAK int sdr_hw_udp_send_iq(const void *packet, size_t length) {
    (void)packet;
    (void)length;
    return 0;
}

SDR_WEAK int sdr_hw_udp_send_status(const void *payload, size_t length) {
    (void)payload;
    (void)length;
    return 0;
}
