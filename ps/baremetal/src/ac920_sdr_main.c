#include <stdio.h>
#include <string.h>

#include "lwip/err.h"
#include "lwip/ip_addr.h"
#include "lwip/mem.h"
#include "lwip/tcp.h"
#include "netif/xadapter.h"
#include "platform.h"
#include "platform_config.h"
#include "sdr_control.h"
#include "sdr_hw_ac920.h"
#include "xgpiops.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xstatus.h"

#if LWIP_IPV6 != 0
#error "AC920 SDR bridge expects IPv4 lwIP configuration"
#endif

#define SDR_TCP_CONTROL_PORT 9000U
#define SDR_STATUS_INTERVAL_MS 200U

void lwip_init(void);
void tcp_fasttmr(void);
void tcp_slowtmr(void);

extern volatile int TcpFastTmrFlag;
extern volatile int TcpSlowTmrFlag;

static struct netif g_netif;
struct netif *echo_netif = &g_netif;
static sdr_control_t g_sdr;

typedef struct {
    char line[2048];
    size_t used;
} sdr_tcp_conn_t;

static void print_ip_addr(const char *label, const ip_addr_t *ip) {
    xil_printf("%s%d.%d.%d.%d\r\n",
               label,
               ip4_addr1(ip),
               ip4_addr2(ip),
               ip4_addr3(ip),
               ip4_addr4(ip));
}

static void ac920_release_pl_reset(void) {
#ifdef XPAR_XGPIOPS_0_DEVICE_ID
    XGpioPs gpio;
    XGpioPs_Config *cfg = XGpioPs_LookupConfig(XPAR_XGPIOPS_0_DEVICE_ID);

    if (cfg == NULL) {
        xil_printf("AC920 SDR: GPIO config not found; PL reset GPIO not touched\r\n");
        return;
    }
    if (XGpioPs_CfgInitialize(&gpio, cfg, cfg->BaseAddr) != XST_SUCCESS) {
        xil_printf("AC920 SDR: GPIO init failed; PL reset GPIO not touched\r\n");
        return;
    }

    XGpioPs_SetDirectionPin(&gpio, 78, 1);
    XGpioPs_SetOutputEnablePin(&gpio, 78, 1);
    XGpioPs_WritePin(&gpio, 78, 1);
#endif
}

static err_t sdr_tcp_send_response(struct tcp_pcb *tpcb, const char *response, size_t length) {
    err_t err;

    if (length == 0U) {
        return ERR_OK;
    }
    if (length > tcp_sndbuf(tpcb)) {
        xil_printf("AC920 SDR: TCP send buffer full, dropping response\r\n");
        return ERR_MEM;
    }

    err = tcp_write(tpcb, response, (u16_t)length, TCP_WRITE_FLAG_COPY);
    if (err == ERR_OK) {
        tcp_output(tpcb);
    }
    return err;
}

static void sdr_tcp_handle_line(struct tcp_pcb *tpcb, sdr_tcp_conn_t *conn) {
    char response[2048];
    size_t response_len;

    conn->line[conn->used] = '\0';
    response_len = sdr_control_handle_line(&g_sdr, conn->line, response, sizeof(response));
    (void)sdr_tcp_send_response(tpcb, response, response_len);
    conn->used = 0U;
}

static err_t sdr_tcp_recv(void *arg, struct tcp_pcb *tpcb, struct pbuf *p, err_t err) {
    sdr_tcp_conn_t *conn = (sdr_tcp_conn_t *)arg;
    struct pbuf *q;

    if (p == NULL) {
        tcp_arg(tpcb, NULL);
        tcp_recv(tpcb, NULL);
        tcp_close(tpcb);
        if (conn != NULL) {
            mem_free(conn);
        }
        return ERR_OK;
    }

    if (err != ERR_OK) {
        pbuf_free(p);
        return err;
    }

    tcp_recved(tpcb, p->tot_len);
    for (q = p; q != NULL; q = q->next) {
        const char *payload = (const char *)q->payload;
        u16_t i;

        for (i = 0; i < q->len; i++) {
            char ch = payload[i];

            if (ch == '\r') {
                continue;
            }
            if (ch == '\n') {
                sdr_tcp_handle_line(tpcb, conn);
                continue;
            }
            if (conn->used + 1U >= sizeof(conn->line)) {
                const char too_long[] =
                    "{\"ok\":false,\"error\":{\"code\":\"invalid_field\",\"message\":\"control line too long\"}}\n";
                (void)sdr_tcp_send_response(tpcb, too_long, sizeof(too_long) - 1U);
                conn->used = 0U;
                continue;
            }
            conn->line[conn->used++] = ch;
        }
    }

    pbuf_free(p);
    return ERR_OK;
}

static void sdr_tcp_err(void *arg, err_t err) {
    sdr_tcp_conn_t *conn = (sdr_tcp_conn_t *)arg;
    (void)err;
    if (conn != NULL) {
        mem_free(conn);
    }
}

static err_t sdr_tcp_accept(void *arg, struct tcp_pcb *newpcb, err_t err) {
    sdr_tcp_conn_t *conn;
    const char *peer_ip;

    (void)arg;
    if (err != ERR_OK || newpcb == NULL) {
        return err;
    }

    conn = (sdr_tcp_conn_t *)mem_malloc(sizeof(*conn));
    if (conn == NULL) {
        tcp_abort(newpcb);
        return ERR_ABRT;
    }
    memset(conn, 0, sizeof(*conn));

    peer_ip = ipaddr_ntoa(&newpcb->remote_ip);
    if (peer_ip != NULL) {
        sdr_control_set_peer_ip(&g_sdr, peer_ip);
        xil_printf("AC920 SDR: TCP control peer %s:%u\r\n", peer_ip, newpcb->remote_port);
    }

    tcp_arg(newpcb, conn);
    tcp_recv(newpcb, sdr_tcp_recv);
    tcp_err(newpcb, sdr_tcp_err);
    return ERR_OK;
}

static int sdr_start_tcp_control(void) {
    struct tcp_pcb *pcb;
    err_t err;

    pcb = tcp_new_ip_type(IPADDR_TYPE_ANY);
    if (pcb == NULL) {
        xil_printf("AC920 SDR: tcp_new failed\r\n");
        return -1;
    }

    err = tcp_bind(pcb, IP_ANY_TYPE, SDR_TCP_CONTROL_PORT);
    if (err != ERR_OK) {
        xil_printf("AC920 SDR: bind TCP %u failed: %d\r\n", SDR_TCP_CONTROL_PORT, err);
        tcp_close(pcb);
        return -1;
    }

    pcb = tcp_listen(pcb);
    if (pcb == NULL) {
        xil_printf("AC920 SDR: tcp_listen failed\r\n");
        return -1;
    }

    tcp_accept(pcb, sdr_tcp_accept);
    xil_printf("AC920 SDR: TCP control listening on port %u\r\n", SDR_TCP_CONTROL_PORT);
    return 0;
}

int main(void) {
    ip_addr_t ipaddr;
    ip_addr_t netmask;
    ip_addr_t gateway;
    unsigned char mac_ethernet_address[] = {0x00, 0x0a, 0x35, 0x01, 0xfe, 0xc0};

    Xil_DCacheEnable();
    ac920_release_pl_reset();
    init_platform();

    IP4_ADDR(&ipaddr, 192, 168, 10, 2);
    IP4_ADDR(&netmask, 255, 255, 255, 0);
    IP4_ADDR(&gateway, 192, 168, 10, 1);

    xil_printf("\r\nAC920 SDR PS bridge starting\r\n");
    lwip_init();

    echo_netif = &g_netif;
    if (!xemac_add(&g_netif, &ipaddr, &netmask, &gateway, mac_ethernet_address, PLATFORM_EMAC_BASEADDR)) {
        xil_printf("AC920 SDR: failed to add network interface\r\n");
        return -1;
    }
    netif_set_default(&g_netif);
#ifndef SDT
    platform_enable_interrupts();
#endif
    netif_set_up(&g_netif);

    print_ip_addr("Board IP: ", &ipaddr);
    print_ip_addr("Netmask : ", &netmask);
    print_ip_addr("Gateway : ", &gateway);

    sdr_control_init(&g_sdr);
    if (sdr_hw_init() != 0) {
        xil_printf("AC920 SDR: hardware init failed\r\n");
        return -1;
    }
    if (sdr_start_tcp_control() != 0) {
        return -1;
    }

    while (1) {
        if (TcpFastTmrFlag) {
            tcp_fasttmr();
            TcpFastTmrFlag = 0;
        }
        if (TcpSlowTmrFlag) {
            tcp_slowtmr();
            TcpSlowTmrFlag = 0;
        }

        xemacif_input(&g_netif);
        (void)sdr_hw_ac920_poll_iq_dma(&g_sdr);
        sdr_hw_ac920_poll_status(&g_sdr, SDR_STATUS_INTERVAL_MS);
    }

    cleanup_platform();
    return 0;
}
