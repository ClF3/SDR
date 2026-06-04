# Extra timing model for the AC920 vendor-project SDR overlay.
#
# The vendor ADC input max delay is kept from the demo XDC. The min delay uses
# a later overlay override so the data-eye close edge is modeled after the
# delayed IDDRE1 capture edge seen on this board build.
set adc1_data_ports [get_ports -quiet {adc1_data_p_0[*] adc1_data_n_0[*]}]
if {[llength $adc1_data_ports] > 0} {
    set_input_delay -clock [get_clocks adc1_clk] -rise -min 2.800 $adc1_data_ports
    set_input_delay -clock [get_clocks adc1_clk] -clock_fall -fall -min 2.800 $adc1_data_ports
}

# The ADC sample clock and the PS-generated AXI/stream clock are independent.
# The SDR core crosses this boundary through explicit CDC logic, so timing
# analysis should not invent a related-clock requirement between them.
set_clock_groups -asynchronous -group [get_clocks adc1_clk] -group [get_clocks clk_pl_1]
