#include "sdr_hw_ac920.h"

#include <stddef.h>
#include <stdint.h>

#include "lwip/ip_addr.h"
#include "lwip/pbuf.h"
#include "lwip/sys.h"
#include "lwip/udp.h"
#include "xaxidma.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "xiltimer.h"
#include "xparameters.h"
#include "xstatus.h"

#include "sdr_regs.h"

#ifndef SDR_AXI_BASEADDR
#if defined(XPAR_SDR_TOP_0_S_AXI_BASEADDR)
#define SDR_AXI_BASEADDR XPAR_SDR_TOP_0_S_AXI_BASEADDR
#elif defined(XPAR_SDR_VENDOR_BD_CORE_0_S00_AXI_BASEADDR)
#define SDR_AXI_BASEADDR XPAR_SDR_VENDOR_BD_CORE_0_S00_AXI_BASEADDR
#elif defined(XPAR_SDR_VENDOR_BD_CORE_0_BASEADDR)
#define SDR_AXI_BASEADDR XPAR_SDR_VENDOR_BD_CORE_0_BASEADDR
#elif defined(XPAR_SDR_TOP_0_BASEADDR)
#define SDR_AXI_BASEADDR XPAR_SDR_TOP_0_BASEADDR
#elif defined(XPAR_SDR_PL_CORE_0_S_AXI_BASEADDR)
#define SDR_AXI_BASEADDR XPAR_SDR_PL_CORE_0_S_AXI_BASEADDR
#else
#error "Define SDR_AXI_BASEADDR to the sdr_top AXI-Lite base address from xparameters.h"
#endif
#endif

#ifndef SDR_AXI_DMA_DEVICE_ID
#if defined(XPAR_AXIDMA_0_DEVICE_ID)
#define SDR_AXI_DMA_DEVICE_ID XPAR_AXIDMA_0_DEVICE_ID
#elif defined(XPAR_AXI_DMA_0_DEVICE_ID)
#define SDR_AXI_DMA_DEVICE_ID XPAR_AXI_DMA_0_DEVICE_ID
#endif
#endif

#ifndef SDR_AXI_DMA_BASEADDR
#if defined(XPAR_XAXIDMA_0_BASEADDR)
#define SDR_AXI_DMA_BASEADDR XPAR_XAXIDMA_0_BASEADDR
#elif defined(XPAR_AXI_DMA_0_BASEADDR)
#define SDR_AXI_DMA_BASEADDR XPAR_AXI_DMA_0_BASEADDR
#elif defined(XPAR_AXIDMA_0_BASEADDR)
#define SDR_AXI_DMA_BASEADDR XPAR_AXIDMA_0_BASEADDR
#endif
#endif

#ifndef SDR_DMA_CACHELINE_BYTES
#define SDR_DMA_CACHELINE_BYTES 64U
#endif

static XAxiDma g_iq_dma;
static int g_iq_dma_ready;
static int g_iq_dma_running;
static int g_iq_dma_armed;
static uint8_t g_iq_dma_buffer[SDR_IQ_PACKET_BYTES] __attribute__((aligned(SDR_DMA_CACHELINE_BYTES)));

static struct udp_pcb *g_iq_pcb;
static struct udp_pcb *g_status_pcb;
static ip_addr_t g_udp_addr;
static uint16_t g_iq_port;
static uint16_t g_status_port;
static uint64_t g_last_status_ms;

static uint64_t sdr_time_millis(void) {
    XTime now;

    XTime_GetTime(&now);
    return ((uint64_t)now * 1000ULL) / (uint64_t)COUNTS_PER_SECOND;
}

static int sdr_arm_iq_dma(void) {
    int status;

    if (!g_iq_dma_ready) {
        return -1;
    }
    Xil_DCacheInvalidateRange((UINTPTR)g_iq_dma_buffer, SDR_IQ_PACKET_BYTES);
    status = XAxiDma_SimpleTransfer(
        &g_iq_dma,
        (UINTPTR)g_iq_dma_buffer,
        SDR_IQ_PACKET_BYTES,
        XAXIDMA_DEVICE_TO_DMA);
    if (status != XST_SUCCESS) {
        g_iq_dma_armed = 0;
        return -1;
    }
    g_iq_dma_armed = 1;
    return 0;
}

static int sdr_udp_send(struct udp_pcb *pcb, const void *payload, size_t length, uint16_t port) {
    struct pbuf *pbuf;
    err_t err;

    if (pcb == NULL || payload == NULL || length == 0U || length > 0xffffU || port == 0U) {
        return -1;
    }

    pbuf = pbuf_alloc(PBUF_TRANSPORT, (u16_t)length, PBUF_RAM);
    if (pbuf == NULL) {
        return -1;
    }
    err = pbuf_take(pbuf, payload, (u16_t)length);
    if (err == ERR_OK) {
        err = udp_sendto(pcb, pbuf, &g_udp_addr, port);
    }
    pbuf_free(pbuf);
    return err == ERR_OK ? 0 : -1;
}

int sdr_hw_init(void) {
    XAxiDma_Config *dma_config;
    int status;

#ifdef SDT
#ifndef SDR_AXI_DMA_BASEADDR
#error "Define SDR_AXI_DMA_BASEADDR to the AXI DMA base address from xparameters.h"
#endif
    dma_config = XAxiDma_LookupConfig((UINTPTR)SDR_AXI_DMA_BASEADDR);
#else
#ifdef SDR_AXI_DMA_DEVICE_ID
    dma_config = XAxiDma_LookupConfig(SDR_AXI_DMA_DEVICE_ID);
#elif defined(SDR_AXI_DMA_BASEADDR)
    dma_config = XAxiDma_LookupConfigBaseAddr((UINTPTR)SDR_AXI_DMA_BASEADDR);
#else
#error "Define SDR_AXI_DMA_DEVICE_ID or SDR_AXI_DMA_BASEADDR for AXI DMA from xparameters.h"
#endif
#endif
    if (dma_config == NULL) {
        return -1;
    }

    status = XAxiDma_CfgInitialize(&g_iq_dma, dma_config);
    if (status != XST_SUCCESS) {
        return -1;
    }
    if (XAxiDma_HasSg(&g_iq_dma)) {
        return -1;
    }

    XAxiDma_IntrDisable(&g_iq_dma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);
    XAxiDma_IntrDisable(&g_iq_dma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DMA_TO_DEVICE);

    g_iq_dma_ready = 1;
    g_iq_dma_running = 0;
    g_iq_dma_armed = 0;

    if (g_iq_pcb == NULL) {
        g_iq_pcb = udp_new();
    }
    if (g_status_pcb == NULL) {
        g_status_pcb = udp_new();
    }
    return (g_iq_pcb != NULL && g_status_pcb != NULL) ? 0 : -1;
}

uint64_t sdr_hw_millis(void) {
    return sdr_time_millis();
}

u32_t sys_now(void) __attribute__((weak));
u32_t sys_now(void) {
    return (u32_t)sdr_time_millis();
}

uint32_t sdr_hw_read_reg(uint32_t offset) {
    return Xil_In32((UINTPTR)SDR_AXI_BASEADDR + offset);
}

void sdr_hw_write_reg(uint32_t offset, uint32_t value) {
    Xil_Out32((UINTPTR)SDR_AXI_BASEADDR + offset, value);
}

void sdr_hw_read_status(sdr_hw_status_t *status) {
    if (status == NULL) {
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

int sdr_hw_start_iq_dma(void) {
    if (!g_iq_dma_ready) {
        return -1;
    }
    g_iq_dma_running = 1;
    if (g_iq_dma_armed) {
        return 0;
    }
    return sdr_arm_iq_dma();
}

void sdr_hw_stop_iq_dma(void) {
    g_iq_dma_running = 0;
    g_iq_dma_armed = 0;
    if (g_iq_dma_ready) {
        XAxiDma_Reset(&g_iq_dma);
        while (!XAxiDma_ResetIsDone(&g_iq_dma)) {
        }
    }
}

int sdr_hw_set_udp_peer(const sdr_udp_peer_t *peer) {
    if (peer == NULL || peer->iq_port == 0U || peer->status_port == 0U) {
        return -1;
    }
    if (g_iq_pcb == NULL) {
        g_iq_pcb = udp_new();
    }
    if (g_status_pcb == NULL) {
        g_status_pcb = udp_new();
    }
    if (g_iq_pcb == NULL || g_status_pcb == NULL) {
        return -1;
    }
    if (!ipaddr_aton(peer->destination_ip, &g_udp_addr)) {
        return -1;
    }
    g_iq_port = peer->iq_port;
    g_status_port = peer->status_port;
    return 0;
}

int sdr_hw_udp_send_iq(const void *packet, size_t length) {
    return sdr_udp_send(g_iq_pcb, packet, length, g_iq_port);
}

int sdr_hw_udp_send_status(const void *payload, size_t length) {
    return sdr_udp_send(g_status_pcb, payload, length, g_status_port);
}

int sdr_hw_ac920_poll_iq_dma(sdr_control_t *control) {
    int rc;

    if (!g_iq_dma_running || !g_iq_dma_armed) {
        return 0;
    }
    if (XAxiDma_Busy(&g_iq_dma, XAXIDMA_DEVICE_TO_DMA)) {
        return 0;
    }

    g_iq_dma_armed = 0;
    Xil_DCacheInvalidateRange((UINTPTR)g_iq_dma_buffer, SDR_IQ_PACKET_BYTES);
    rc = sdr_control_forward_iq_packet(control, g_iq_dma_buffer, SDR_IQ_PACKET_BYTES);
    if (g_iq_dma_running && sdr_arm_iq_dma() != 0) {
        return -1;
    }
    return rc;
}

void sdr_hw_ac920_poll_status(sdr_control_t *control, uint32_t interval_ms) {
    char status_json[1600];
    size_t length;
    uint64_t now_ms = sdr_hw_millis();

    if (interval_ms == 0U) {
        interval_ms = 1000U;
    }
    if (now_ms - g_last_status_ms < interval_ms) {
        return;
    }
    g_last_status_ms = now_ms;

    length = sdr_control_build_status_json(control, status_json, sizeof(status_json));
    if (length > 0U) {
        (void)sdr_hw_udp_send_status(status_json, length);
    }
}
