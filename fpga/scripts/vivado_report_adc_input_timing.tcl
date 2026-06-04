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

open_checkpoint $routed_dcp
set adc_ports [get_ports -quiet -regexp {adc1_data_[pn]_0\[[0-9]+\]}]
set iddr_d_pins [get_pins -quiet -hier *IDDR_adc1_data/D]

puts "AC920 ADC input max timing:"
report_timing -from $adc_ports -to $iddr_d_pins -delay_type max -max_paths 10

puts ""
puts "AC920 ADC input min timing:"
report_timing -from $adc_ports -to $iddr_d_pins -delay_type min -max_paths 10
