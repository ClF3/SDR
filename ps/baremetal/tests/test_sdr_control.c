#include <stdio.h>
#include <string.h>

#include "sdr_control.h"

static int require_contains(const char *haystack, const char *needle) {
    if (strstr(haystack, needle) != 0) {
        return 0;
    }
    fprintf(stderr, "missing substring: %s\nresponse: %s\n", needle, haystack);
    return 1;
}

int main(void) {
    sdr_control_t control;
    char response[2048];
    int failures = 0;

    sdr_control_init(&control);
    sdr_control_set_peer_ip(&control, "127.0.0.1");

    sdr_control_handle_line(
        &control,
        "{\"request_id\":1,\"cmd\":\"hello\",\"protocol_version\":1,"
        "\"client_name\":\"smoke\",\"udp\":{\"destination_ip\":\"127.0.0.1\","
        "\"iq_port\":9001,\"psd_port\":9002,\"status_port\":9003}}\n",
        response,
        sizeof(response));
    failures += require_contains(response, "\"ok\":true");
    failures += require_contains(response, "\"max_iq_streams\":1");

    sdr_control_handle_line(
        &control,
        "{\"request_id\":2,\"cmd\":\"set_rx\",\"stream_id\":0,\"adc_channel\":0,"
        "\"frequency_hz\":98500000,\"mode\":\"WFM\",\"iq_sample_rate_hz\":1000000,"
        "\"bandwidth_hz\":250000,\"sample_format\":\"SC16_LE\",\"enable\":true}\n",
        response,
        sizeof(response));
    failures += require_contains(response, "\"ok\":true");
    failures += require_contains(response, "\"decimation\":250");

    sdr_control_handle_line(&control, "{\"request_id\":3,\"cmd\":\"get_status\"}\n", response,
                            sizeof(response));
    failures += require_contains(response, "\"ok\":true");
    failures += require_contains(response, "\"status\"");

    sdr_control_handle_line(
        &control,
        "{\"request_id\":4,\"cmd\":\"set_psd\",\"enable\":true,\"output_bins\":4096}\n",
        response,
        sizeof(response));
    failures += require_contains(response, "\"ok\":false");
    failures += require_contains(response, "PSD is not implemented");

    sdr_control_handle_line(&control, "{\"request_id\":5,\"cmd\":\"stop_all\"}\n", response,
                            sizeof(response));
    failures += require_contains(response, "\"ok\":true");

    if (failures != 0) {
        return 1;
    }
    puts("PASS: sdr_control smoke");
    return 0;
}
