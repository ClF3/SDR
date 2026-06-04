set script_dir [file dirname [file normalize [info script]]]
set fpga_dir [file normalize [file join $script_dir ..]]
set default_bit [file join $fpga_dir build ac920_vendor_sdr CM3432_DualChannel_TCP.runs impl_1 top.bit]

if {[info exists ::env(AC920_BIT)]} {
    set bit_path [file normalize $::env(AC920_BIT)]
} else {
    set bit_path [file normalize $default_bit]
}

if {![file exists $bit_path]} {
    error "AC920 bitstream does not exist: $bit_path"
}

puts "AC920 program: bitstream $bit_path"

open_hw_manager
connect_hw_server
open_hw_target

set devices [get_hw_devices -quiet]
if {[llength $devices] == 0} {
    error "No JTAG hardware devices found. Check board power, USB/JTAG cable, and drivers."
}

set device [lindex $devices 0]
current_hw_device $device
refresh_hw_device $device

puts "AC920 program: programming device $device"
set_property PROGRAM.FILE $bit_path $device
program_hw_devices $device
refresh_hw_device $device

puts "AC920 program complete."
