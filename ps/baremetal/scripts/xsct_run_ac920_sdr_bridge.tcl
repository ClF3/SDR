if {$argc < 2} {
    error "usage: xsct_run_ac920_sdr_bridge.tcl <ac920_sdr_bridge.elf> <psu_init.tcl>"
}

set elf_path [file normalize [lindex $argv 0]]
set psu_init_path [file normalize [lindex $argv 1]]

if {![file exists $elf_path]} {
    error "ELF does not exist: $elf_path"
}
if {![file exists $psu_init_path]} {
    error "psu_init.tcl does not exist: $psu_init_path"
}

proc ac920_set_target {filter_expr description} {
    puts "AC920 XSCT: selecting $description target"
    if {[catch {targets -set -filter $filter_expr} err]} {
        puts "AC920 XSCT: available targets:"
        catch {targets}
        error "Could not select $description target with filter {$filter_expr}: $err"
    }
}

puts "AC920 XSCT: ELF $elf_path"
puts "AC920 XSCT: psu_init $psu_init_path"

connect
after 500

ac920_set_target {name =~ "*PSU*"} "PSU"
if {[info exists ::env(AC920_XSCT_SYSTEM_RESET)] && $::env(AC920_XSCT_SYSTEM_RESET) ne "0"} {
    puts "AC920 XSCT: system reset"
    catch {rst -system}
    after 1000
}

if {[info exists ::env(AC920_XSCT_SKIP_PSU_INIT)] && $::env(AC920_XSCT_SKIP_PSU_INIT) ne "0"} {
    puts "AC920 XSCT: skipping psu_init sequence"
} else {
    source $psu_init_path

    foreach init_proc {psu_init psu_ps_pl_isolation_removal psu_ps_pl_reset_config} {
        if {[llength [info commands $init_proc]] > 0} {
            puts "AC920 XSCT: running $init_proc"
            $init_proc
        } else {
            puts "AC920 XSCT: $init_proc not present in psu_init.tcl, skipping"
        }
    }
}

ac920_set_target {name =~ "*Cortex-A53 #0*"} "Cortex-A53 #0"
catch {stop}
catch {rst -processor -clear-registers}
after 200

puts "AC920 XSCT: downloading ELF"
dow $elf_path

puts "AC920 XSCT: starting Cortex-A53 #0"
con
puts "AC920 XSCT: AC920 SDR bridge is running"
