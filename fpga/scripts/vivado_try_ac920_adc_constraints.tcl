set script_dir [file dirname [file normalize [info script]]]
set fpga_dir [file normalize [file join $script_dir ..]]

if {[info exists ::env(AC920_PROJECT)]} {
    set project_path [file normalize $::env(AC920_PROJECT)]
} else {
    set project_path [file join $fpga_dir build ac920_vendor_sdr CM3432_DualChannel_TCP.xpr]
}

set run_dir [file join [file dirname $project_path] CM3432_DualChannel_TCP.runs impl_1]
set routed_dcp [file join $run_dir top_routed.dcp]

if {![file exists $routed_dcp]} {
    error "Routed checkpoint does not exist: $routed_dcp"
}

proc print_short_summary {label} {
    puts ""
    puts "==== $label ===="
    report_timing_summary -max_paths 5 -warn_on_violation
}

open_checkpoint $routed_dcp
set adc_ports [get_ports -quiet {adc1_data_p_0[*] adc1_data_n_0[*]}]
puts "AC920 adc port count: [llength $adc_ports]"

print_short_summary "baseline"

foreach min_delay {2.000 2.400 2.600 2.800 3.000} {
    puts ""
    puts "==== applying adc input min $min_delay ns ===="
    set_input_delay -clock [get_clocks adc1_clk] -rise -min $min_delay $adc_ports
    set_input_delay -clock [get_clocks adc1_clk] -clock_fall -fall -min $min_delay $adc_ports
    report_timing_summary -max_paths 3 -warn_on_violation
}
