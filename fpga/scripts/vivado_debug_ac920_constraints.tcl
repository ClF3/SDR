set script_dir [file dirname [file normalize [info script]]]
set fpga_dir [file normalize [file join $script_dir ..]]

if {[info exists ::env(AC920_PROJECT)]} {
    set project_path [file normalize $::env(AC920_PROJECT)]
} else {
    set project_path [file join $fpga_dir build ac920_vendor_sdr CM3432_DualChannel_TCP.xpr]
}

open_project $project_path

puts "AC920 constraint files:"
foreach f [get_files -quiet -of_objects [get_filesets constrs_1] *.xdc] {
    set order ""
    catch {set order [get_property processing_order $f]}
    puts "  $order $f"
}

set adc_ports [get_ports -quiet -regexp {adc1_data_[pn]_0\[[0-9]+\]}]
puts "AC920 adc regexp port count: [llength $adc_ports]"
foreach p [lsort $adc_ports] {
    puts "  $p"
}

set literal_ports [get_ports -quiet {adc1_data_p_0[*] adc1_data_n_0[*]}]
puts "AC920 adc literal port count: [llength $literal_ports]"
foreach p [lsort $literal_ports] {
    puts "  $p"
}

