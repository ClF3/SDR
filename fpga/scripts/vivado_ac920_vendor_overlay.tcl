set script_dir [file dirname [file normalize [info script]]]
set fpga_dir [file normalize [file join $script_dir ..]]
set repo_dir [file normalize [file join $fpga_dir ..]]

if {[info exists ::env(SDR_REPO_DIR)]} {
    set repo_dir [file normalize $::env(SDR_REPO_DIR)]
    set fpga_dir [file join $repo_dir fpga]
}

if {![info exists ::env(AC920_PROJECT)]} {
    error "AC920_PROJECT must point to CM3432_DualChannel_TCP.xpr"
}

set project_path [file normalize $::env(AC920_PROJECT)]
set project_dir [file dirname $project_path]
set bd_path [file join $project_dir CM3432_DualChannel_TCP.srcs sources_1 bd sys sys.bd]

if {![file exists $project_path]} {
    error "Vivado project does not exist: $project_path"
}
if {![file exists $bd_path]} {
    error "Block design does not exist: $bd_path"
}

proc add_if_exists {files} {
    set existing {}
    foreach f $files {
        if {[file exists $f]} {
            lappend existing $f
        } else {
            puts "WARNING: missing source $f"
        }
    }
    if {[llength $existing] > 0} {
        add_files -fileset sources_1 -norecurse $existing
    }
}

proc connect_pin_force {src dst} {
    set src_obj [get_bd_pins -quiet $src]
    set dst_obj [get_bd_pins -quiet $dst]
    if {[llength $src_obj] == 0} {
        set src_obj [get_bd_ports -quiet $src]
    }
    if {[llength $dst_obj] == 0} {
        set dst_obj [get_bd_ports -quiet $dst]
    }
    if {[llength $src_obj] == 0 || [llength $dst_obj] == 0} {
        puts "WARNING: cannot connect $src -> $dst"
        return
    }
    set old_nets [get_bd_nets -quiet -of_objects $dst_obj]
    if {[llength $old_nets] > 0} {
        catch {disconnect_bd_net $old_nets $dst_obj}
    }
    connect_bd_net $src_obj $dst_obj
}

proc connect_intf_force {src dst} {
    set src_obj [get_bd_intf_pins -quiet $src]
    set dst_obj [get_bd_intf_pins -quiet $dst]
    if {[llength $src_obj] == 0 || [llength $dst_obj] == 0} {
        puts "WARNING: cannot connect interface $src -> $dst"
        return 0
    }
    set old_nets [get_bd_intf_nets -quiet -of_objects $dst_obj]
    if {[llength $old_nets] > 0} {
        catch {disconnect_bd_intf_net $old_nets $dst_obj}
    }
    connect_bd_intf_net $src_obj $dst_obj
    return 1
}

puts "AC920 overlay: opening project $project_path"
open_project $project_path

set rtl_files [list \
    [file join $fpga_dir rtl top sdr_vendor_bd_core.v] \
    [file join $fpga_dir rtl top sdr_pl_core.v] \
    [file join $fpga_dir rtl ctrl axi_lite_slave.v] \
    [file join $fpga_dir rtl ctrl csr_regfile.v] \
    [file join $fpga_dir rtl adc adc_format_convert.v] \
    [file join $fpga_dir rtl monitor adc_level_monitor.v] \
    [file join $fpga_dir rtl dsp nco.v] \
    [file join $fpga_dir rtl dsp cordic_sincos.v] \
    [file join $fpga_dir rtl dsp mixer_real_to_iq.v] \
    [file join $fpga_dir rtl dsp cic_decimator.v] \
    [file join $fpga_dir rtl dsp cic_comp_fir.v] \
    [file join $fpga_dir rtl dsp iq_gain_sat.v] \
    [file join $fpga_dir rtl dsp dc_offset_remove.v] \
    [file join $fpga_dir rtl dsp ddc_core.v] \
    [file join $fpga_dir rtl stream iq_packetizer.v] \
    [file join $fpga_dir rtl stream timestamp_counter.v] \
    [file join $fpga_dir rtl stream axis_async_fifo.v] \
    [file join $fpga_dir rtl util reset_sync.v] \
    [file join $fpga_dir rtl util config_sync.v] \
    [file join $fpga_dir rtl util pulse_sync.v] \
]

puts "AC920 overlay: adding SDR RTL sources"
add_if_exists $rtl_files
update_compile_order -fileset sources_1

puts "AC920 overlay: opening block design $bd_path"
open_bd_design $bd_path

if {[llength [get_bd_cells -quiet sdr_vendor_bd_core_0]] == 0} {
    puts "AC920 overlay: creating module reference sdr_vendor_bd_core_0"
    create_bd_cell -type module -reference sdr_vendor_bd_core sdr_vendor_bd_core_0
}
if {[llength [get_bd_cells -quiet sdr_vendor_bd_core_0]] == 0} {
    error "Failed to create sdr_vendor_bd_core_0. Check that sdr_vendor_bd_core.v was added and recognized by Vivado."
}

foreach old_cell {fifo2axis_write_0 adc_sample_ctrl_0} {
    set cell [get_bd_cells -quiet $old_cell]
    if {[llength $cell] > 0} {
        puts "AC920 overlay: deleting old cell $old_cell"
        delete_bd_objs $cell
    }
}

if {![connect_intf_force sdr_vendor_bd_core_0/M_AXIS axi_dma_0/S_AXIS_S2MM]} {
    error "Failed to connect sdr_vendor_bd_core_0/M_AXIS to axi_dma_0/S_AXIS_S2MM"
}
if {![connect_intf_force axi_smc/M00_AXI sdr_vendor_bd_core_0/S00_AXI]} {
    error "Failed to connect axi_smc/M00_AXI to sdr_vendor_bd_core_0/S00_AXI"
}

connect_pin_force zynq_ultra_ps_e_0/pl_clk1 sdr_vendor_bd_core_0/s00_axi_aclk
connect_pin_force zynq_ultra_ps_e_0/pl_clk1 sdr_vendor_bd_core_0/M_AXIS_ACLK
connect_pin_force M_AXIS_FIFO_CLK_0 sdr_vendor_bd_core_0/M_AXIS_FIFO_CLK
connect_pin_force rst_clk_wiz_0_99M/peripheral_aresetn sdr_vendor_bd_core_0/s00_axi_aresetn
connect_pin_force rst_clk_wiz_0_99M/peripheral_aresetn sdr_vendor_bd_core_0/M_AXIS_ARESETN

connect_pin_force din_0 sdr_vendor_bd_core_0/din
connect_pin_force din_comb_0 sdr_vendor_bd_core_0/din_comb
connect_pin_force dvalid_0 sdr_vendor_bd_core_0/dvalid

connect_pin_force sdr_vendor_bd_core_0/ADC_Speed_Set ADC_Speed_Set_0
connect_pin_force sdr_vendor_bd_core_0/ChannelSel ChannelSel_0
connect_pin_force sdr_vendor_bd_core_0/ad_sample_en ad_sample_en_0
connect_pin_force sdr_vendor_bd_core_0/reg_conf reg_conf_0

assign_bd_address
set addr_segs [get_bd_addr_segs -quiet zynq_ultra_ps_e_0/Data/SEG_sdr_vendor_bd_core_0*]
if {[llength $addr_segs] == 0} {
    puts "WARNING: address segment for sdr_vendor_bd_core_0 was not found; verify Address Editor manually."
}
foreach seg $addr_segs {
    catch {set_property offset 0x80000000 $seg}
    catch {set_property range 64K $seg}
}

puts "AC920 overlay: validating and saving block design"
validate_bd_design
save_bd_design

make_wrapper -files [get_files $bd_path] -top -force
set wrapper [file join $project_dir CM3432_DualChannel_TCP.gen sources_1 bd sys hdl sys_wrapper.v]
if {[file exists $wrapper]} {
    add_files -fileset sources_1 -norecurse $wrapper
}

update_compile_order -fileset sources_1
save_project

puts "AC920 vendor overlay complete."
puts "Project: $project_path"
puts "BD:      $bd_path"
