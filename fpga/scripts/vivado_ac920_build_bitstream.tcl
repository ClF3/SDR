set script_dir [file dirname [file normalize [info script]]]
set fpga_dir [file normalize [file join $script_dir ..]]
set repo_dir [file normalize [file join $fpga_dir ..]]

if {[info exists ::env(SDR_REPO_DIR)]} {
    set repo_dir [file normalize $::env(SDR_REPO_DIR)]
    set fpga_dir [file join $repo_dir fpga]
}

if {[info exists ::env(AC920_PROJECT)]} {
    set project_path [file normalize $::env(AC920_PROJECT)]
} else {
    set project_path [file join $fpga_dir build ac920_vendor_sdr CM3432_DualChannel_TCP.xpr]
}

if {[info exists ::env(VIVADO_JOBS)]} {
    set jobs $::env(VIVADO_JOBS)
} else {
    set jobs 1
}

if {![file exists $project_path]} {
    error "Vivado project does not exist: $project_path"
}

puts "AC920 bitstream: opening project $project_path"
open_project $project_path
set_param general.maxThreads $jobs

set bd_files [get_files -quiet *CM3432_DualChannel_TCP.srcs/sources_1/bd/sys/sys.bd]
if {[llength $bd_files] > 0} {
    puts "AC920 bitstream: generating BD targets"
    generate_target all [lindex $bd_files 0]
}

update_compile_order -fileset sources_1

set synth_status [get_property STATUS [get_runs synth_1]]
puts "AC920 bitstream: synth_1 status: $synth_status"
if {[string first "Complete" $synth_status] < 0} {
    reset_run synth_1
    launch_runs synth_1 -jobs $jobs
    wait_on_run synth_1
}

set synth_status [get_property STATUS [get_runs synth_1]]
if {[string first "Complete" $synth_status] < 0} {
    error "synth_1 did not complete: $synth_status"
}

puts "AC920 bitstream: resetting impl_1"
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "AC920 bitstream: impl_1 status: $impl_status"
if {[string first "Complete" $impl_status] < 0} {
    error "impl_1 did not complete: $impl_status"
}

set bit_file [file join [file dirname $project_path] CM3432_DualChannel_TCP.runs impl_1 top.bit]
if {![file exists $bit_file]} {
    error "Bitstream was not produced at expected path: $bit_file"
}

set timing_report [file join [file dirname $project_path] CM3432_DualChannel_TCP.runs impl_1 top_timing_summary_routed.rpt]
if {![file exists $timing_report]} {
    error "Routed timing summary was not produced at expected path: $timing_report"
}

set timing_fh [open $timing_report r]
set timing_text [read $timing_fh]
close $timing_fh

if {[string first "Timing constraints are not met" $timing_text] >= 0} {
    error "Bitstream was produced, but routed timing constraints are not met. See: $timing_report"
}

puts "AC920 bitstream complete."
puts "Bitstream: $bit_file"
