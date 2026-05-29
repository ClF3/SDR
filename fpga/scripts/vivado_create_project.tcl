set script_dir [file dirname [file normalize [info script]]]
set fpga_dir [file normalize [file join $script_dir ..]]

if {[info exists ::env(FPGA_PART)]} {
    set fpga_part $::env(FPGA_PART)
} else {
    set fpga_part "xczu4ev-sfvc784-2-i"
}

set build_dir [file join $fpga_dir build vivado]
set proj_dir  [file join $build_dir sdr_fpga]
file mkdir $build_dir

create_project sdr_fpga $proj_dir -part $fpga_part -force

set rtl_files [glob -nocomplain [file join $fpga_dir rtl */*.v]]
add_files -fileset sources_1 $rtl_files
set_property top sdr_top [current_fileset]
set_property verilog_define {USE_XILINX_PRIMS=1} [current_fileset]
update_compile_order -fileset sources_1

set xdc_files [list \
    [file join $fpga_dir constraints clocks.xdc] \
    [file join $fpga_dir constraints pins.xdc] \
    [file join $fpga_dir constraints ac920_acfl3432.xdc] \
]
foreach xdc $xdc_files {
    if {[file exists $xdc]} {
        add_files -fileset constrs_1 $xdc
    }
}

puts "Created Vivado project at $proj_dir"
puts "FPGA_PART=$fpga_part"
puts "Top=sdr_top"
