#ifndef SDR_HW_AC920_H
#define SDR_HW_AC920_H

#include <stdint.h>

#include "sdr_control.h"

int sdr_hw_ac920_poll_iq_dma(sdr_control_t *control);
void sdr_hw_ac920_poll_status(sdr_control_t *control, uint32_t interval_ms);

#endif
