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

proc add_required_sources {files} {
    set missing {}
    set existing {}
    foreach f $files {
        set normalized [file normalize $f]
        if {[file exists $normalized]} {
            lappend existing $normalized
        } else {
            lappend missing $normalized
        }
    }
    if {[llength $missing] > 0} {
        puts "ERROR: missing SDR RTL source files:"
        foreach f $missing {
            puts "  $f"
        }
        error "SDR_REPO_DIR is probably wrong, or this repo checkout does not contain the FPGA RTL files."
    }
    if {[llength $existing] > 0} {
        import_files -fileset sources_1 -norecurse -force $existing
        foreach f $existing {
            set imported [get_files -quiet -of_objects [get_filesets sources_1] *[file tail $f]]
            if {[llength $imported] > 0} {
                catch {set_property file_type Verilog $imported}
                catch {set_property library xil_defaultlib $imported}
                catch {set_property used_in_synthesis true $imported}
                catch {set_property used_in_implementation true $imported}
            }
        }
    }
}

proc add_overlay_constraint {xdc_file} {
    set normalized [file normalize $xdc_file]
    if {![file exists $normalized]} {
        error "Required overlay constraint does not exist: $normalized"
    }

    puts "AC920 overlay: adding constraint $normalized"
    import_files -fileset constrs_1 -norecurse -force $normalized
    set imported [get_files -quiet -of_objects [get_filesets constrs_1] *[file tail $normalized]]
    if {[llength $imported] > 0} {
        catch {set_property used_in_synthesis false $imported}
        catch {set_property used_in_implementation true $imported}
        catch {set_property processing_order LATE $imported}
    }
}

proc print_project_verilog_sources {} {
    set sources [lsort [get_files -quiet -of_objects [get_filesets sources_1] *.v]]
    puts "AC920 overlay: sources_1 Verilog files visible to Vivado:"
    foreach f $sources {
        puts "  $f"
    }
}

proc create_module_ref_with_fallback {module_name source_file cell_name} {
    if {[llength [get_bd_cells -quiet $cell_name]] > 0} {
        return
    }

    puts "AC920 overlay: creating module reference $cell_name from module $module_name"
    set module_err ""
    if {[catch {create_bd_cell -type module -reference $module_name $cell_name} module_err]} {
        puts "WARNING: create_bd_cell by module name failed:"
        puts "  $module_err"
    }
    if {[llength [get_bd_cells -quiet $cell_name]] > 0} {
        return
    }

    puts "AC920 overlay: retrying module reference $cell_name from source file $source_file"
    set file_err ""
    if {[catch {create_bd_cell -type module -reference $source_file $cell_name} file_err]} {
        puts "ERROR: create_bd_cell by source file failed:"
        puts "  $file_err"
        print_project_verilog_sources
        error "Failed to create $cell_name. The RTL source is present, but Vivado IP Integrator could not parse it as an RTL module reference."
    }
}

proc delete_bd_net_if_exists {net_name} {
    set intf_net [get_bd_intf_nets -quiet $net_name]
    if {[llength $intf_net] > 0} {
        puts "AC920 overlay: deleting stale interface net $net_name"
        delete_bd_objs $intf_net
    }

    set net [get_bd_nets -quiet $net_name]
    if {[llength $net] > 0} {
        puts "AC920 overlay: deleting stale net $net_name"
        delete_bd_objs $net
    }
}

proc assign_sdr_csr_address {base range} {
    set slave_seg [get_bd_addr_segs -quiet sdr_vendor_bd_core_0/S00_AXI/reg0]
    set target_space [get_bd_addr_spaces -quiet zynq_ultra_ps_e_0/Data]

    if {[llength $slave_seg] == 0 || [llength $target_space] == 0} {
        puts "WARNING: SDR CSR address objects not found; falling back to automatic address assignment."
        assign_bd_address
        return
    }

    puts "AC920 overlay: assigning SDR CSR at $base range $range"
    set addr_err ""
    if {[catch {assign_bd_address -target_address_space $target_space -offset $base -range $range -force $slave_seg} addr_err]} {
        puts "WARNING: fixed SDR CSR address assignment failed:"
        puts "  $addr_err"
        puts "AC920 overlay: falling back to automatic address assignment."
        assign_bd_address
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
set open_bd [current_bd_design -quiet]
if {[llength $open_bd] > 0} {
    close_bd_design $open_bd
}
set source_mgmt_err ""
if {[catch {set_property source_mgmt_mode All [current_project]} source_mgmt_err]} {
    puts "WARNING: could not set source_mgmt_mode All:"
    puts "  $source_mgmt_err"
}

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
add_required_sources $rtl_files
add_overlay_constraint [file join $fpga_dir constraints ac920_vendor_sdr_overlay.xdc]
update_compile_order -fileset sources_1

set sdr_core_files [get_files -quiet -of_objects [get_filesets sources_1] *sdr_vendor_bd_core.v]
if {[llength $sdr_core_files] == 0} {
    error "sdr_vendor_bd_core.v was not imported into sources_1; cannot create BD module reference."
}
set sdr_core_source [lindex $sdr_core_files 0]
puts "AC920 overlay: using SDR core source $sdr_core_source"

puts "AC920 overlay: opening block design $bd_path"
open_bd_design $bd_path

create_module_ref_with_fallback sdr_vendor_bd_core $sdr_core_source sdr_vendor_bd_core_0
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
foreach old_net {fifo2axis_write_0_M_AXIS adc_sample_ctrl_0_ByteToTrans adc_sample_ctrl_0_Go} {
    delete_bd_net_if_exists $old_net
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

assign_sdr_csr_address 0x90000000 64K

puts "AC920 overlay: validating and saving block design"
validate_bd_design
save_bd_design

make_wrapper -files [get_files $bd_path] -top -force
set wrapper [file join $project_dir CM3432_DualChannel_TCP.gen sources_1 bd sys hdl sys_wrapper.v]
if {[file exists $wrapper]} {
    add_files -fileset sources_1 -norecurse $wrapper
}

update_compile_order -fileset sources_1

puts "AC920 vendor overlay complete."
puts "Project: $project_path"
puts "BD:      $bd_path"
