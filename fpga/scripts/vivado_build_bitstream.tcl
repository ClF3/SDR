set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir vivado_create_project.tcl]

if {[info exists ::env(VIVADO_JOBS)]} {
    set jobs $::env(VIVADO_JOBS)
} else {
    set jobs 4
}

file mkdir [file join $fpga_dir reports timing]
file mkdir [file join $fpga_dir reports utilization]

launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
open_run synth_1
report_utilization -file [file join $fpga_dir reports utilization synth_utilization.rpt]
report_timing_summary -file [file join $fpga_dir reports timing synth_timing_summary.rpt]

if {[info exists ::env(RUN_IMPL)] && $::env(RUN_IMPL) == "1"} {
    launch_runs impl_1 -to_step write_bitstream -jobs $jobs
    wait_on_run impl_1
    open_run impl_1
    report_utilization -file [file join $fpga_dir reports utilization impl_utilization.rpt]
    report_timing_summary -file [file join $fpga_dir reports timing impl_timing_summary.rpt]
    write_bitstream -force [file join $fpga_dir build vivado sdr_fpga.bit]
    puts "Bitstream written to [file join $fpga_dir build vivado sdr_fpga.bit]"
} else {
    puts "Synthesis finished. Set RUN_IMPL=1 after completing board pin constraints to run implementation and bitstream."
}
