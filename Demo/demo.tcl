# Shared Tcl backend for Vivado, XSCT and XSim. Use demo.py as the public entry point.
set demo_here [file dirname [file normalize [info script]]]
set demo_root [file normalize [file join $demo_here ..]]
set demo_impl [file join $demo_root Implementation]
set demo_project [file join $demo_here project]
set demo_output [file join $demo_here output]
set demo_project_name kv260_sensor_demo

proc demo_capture_wave {} {
    set scopes [get_scopes]
    if {[llength $scopes] == 0} {error "XSim returned no design scopes"}
    set top_scope [file dirname [lindex $scopes 0]]
    set objects [get_objects -r *]
    log_wave -r /*
    foreach leaf {clk rst_n start mode busy done} {
        set matches {}
        foreach object $objects {
            if {[file dirname $object] eq $top_scope && [file tail $object] eq $leaf} {
                lappend matches $object
            }
        }
        if {[llength $matches] != 1} {error "Expected one top-level $leaf signal: $matches"}
        add_wave [lindex $matches 0]
    }
    foreach leaf {cycles len cnt} {
        set matches {}
        foreach object $objects {
            if {$leaf eq "cycles" && [file dirname $object] eq $top_scope && [file tail $object] eq $leaf} {
                lappend matches $object
            } elseif {$leaf ne "cycles" && [string match "*/dut/u_controller/$leaf" $object]} {
                lappend matches $object
            }
        }
        if {[llength $matches] != 1} {error "Expected one $leaf signal: $matches"}
        add_wave -radix unsigned [lindex $matches 0]
    }
    run all
    save_wave_config [file join [pwd] ntt_cycles.wcfg]
    quit
}

# XSim sources this same file after elaboration. Dispatch before any Vivado/XSCT command.
if {[llength [info commands log_wave]] > 0 && [llength [info commands get_scopes]] > 0} {
    demo_capture_wave
    return
}

proc demo_psu_init_path {} {
    global demo_output
    set path [file join $demo_output psu_init.tcl]
    if {![file isfile $path]} {error "Missing PS init artifact: $path"}
    return $path
}

proc demo_artix {output_dir} {
    global demo_impl
    set output_dir [file normalize $output_dir]
    file mkdir $output_dir
    cd $output_dir
    set_param general.maxThreads 4
    create_project -in_memory -part xc7a100tfgg676-3
    set_property include_dirs [list [file join $demo_impl rtl utils]] [current_fileset]
    foreach name {ntt_agu ntt_butterfly ntt_controller ntt_core_top ntt_mod_mul_12b ntt_ram_dual ntt_twiddle_rom} {
        read_verilog [file join $demo_impl rtl modules ${name}.v]
    }
    read_xdc [file join $demo_impl constraint ntt.xdc]
    synth_design -top ntt_core_top -part xc7a100tfgg676-3 -mode out_of_context -max_dsp 0 -directive Default
    opt_design
    place_design
    phys_opt_design
    route_design
    report_timing_summary -delay_type min_max -report_unconstrained -file [file join $output_dir timing.rpt]
    report_utilization -hierarchical -file [file join $output_dir utilization_hier.rpt]
    report_utilization -file [file join $output_dir utilization.rpt]
    report_drc -file [file join $output_dir drc.rpt]
    report_route_status -file [file join $output_dir route.rpt]
    report_power -file [file join $output_dir power_vectorless.rpt]
    write_checkpoint -force [file join $output_dir routed.dcp]
    write_verilog -force -mode funcsim [file join $output_dir routed.v]

    foreach delay_type {max min} {
        set path [get_timing_paths -delay_type $delay_type -max_paths 1]
        if {[llength $path] != 1 || [get_property SLACK $path] < 0} {
            error "Artix-7 timing failed for delay type $delay_type"
        }
    }
    puts "ARTIX200_READY=$output_dir"
}

proc demo_build {action} {
    global demo_here demo_impl demo_project demo_output demo_project_name
    if {$action ni {build prepare publish}} {error "Action must be build, prepare or publish"}
    if {$action ne "publish"} {
        if {[file exists $demo_project]} {error "Generated project already exists: $demo_project"}
        if {[current_project -quiet] ne ""} {error "Close the current Vivado project first"}
        create_project $demo_project_name $demo_project -part xck26-sfvc784-2LV-c
        set_property board_part xilinx.com:kv260_som:part0:1.4 [current_project]
        add_files [glob [file join $demo_impl rtl modules *.v]]
        add_files [glob [file join $demo_impl rtl utils *.vh]]
        add_files [file join $demo_here rtl ntt_core_axi_lite.v]
        set_property include_dirs [list [file join $demo_impl rtl utils]] [get_filesets sources_1]

        create_bd_design ntt_system
        set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:* ps]
        apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e -config {apply_board_preset "1"} $ps
        set_property -dict [list \
            CONFIG.PSU__USE__M_AXI_GP0 {1} \
            CONFIG.PSU__USE__M_AXI_GP1 {0} \
            CONFIG.PSU__USE__M_AXI_GP2 {0} \
            CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {200}] $ps

        create_bd_cell -type module -reference ntt_core_axi_lite ntt
        apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
            -config {Master "/ps/M_AXI_HPM0_FPD" Clk_master "/ps/pl_clk0 (200 MHz)" Clk_slave "/ps/pl_clk0 (200 MHz)" Clk_xbar "/ps/pl_clk0 (200 MHz)"} \
            [get_bd_intf_pins ntt/s_axi]
        assign_bd_address
        set ntt_segment [get_bd_addr_segs -of_objects [get_bd_addr_spaces ps/Data] -filter {NAME =~ *ntt*}]
        if {[llength $ntt_segment] != 1} {error "Expected one NTT address segment: $ntt_segment"}
        set_property offset 0xA0000000 $ntt_segment
        set_property range 4K $ntt_segment

        create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:* sensor_gpio
        set_property -dict [list \
            CONFIG.C_GPIO_WIDTH {2} \
            CONFIG.C_ALL_INPUTS {0} \
            CONFIG.C_ALL_OUTPUTS {0} \
            CONFIG.C_DOUT_DEFAULT {0x00000000} \
            CONFIG.C_TRI_DEFAULT {0xFFFFFFFF}] [get_bd_cells sensor_gpio]
        apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
            -config {Master "/ps/M_AXI_HPM0_FPD" Clk_master "/ps/pl_clk0 (200 MHz)" Clk_slave "/ps/pl_clk0 (200 MHz)" Clk_xbar "/ps/pl_clk0 (200 MHz)"} \
            [get_bd_intf_pins sensor_gpio/S_AXI]
        make_bd_intf_pins_external [get_bd_intf_pins sensor_gpio/GPIO]
        set_property name sensor [get_bd_intf_ports GPIO_0]
        assign_bd_address
        set sensor_segment [get_bd_addr_segs -of_objects [get_bd_addr_spaces ps/Data] -filter {NAME =~ *sensor_gpio*}]
        if {[llength $sensor_segment] != 1} {error "Expected one sensor GPIO address segment: $sensor_segment"}
        set_property offset 0xA0010000 $sensor_segment
        set_property range 64K $sensor_segment

        validate_bd_design
        save_bd_design
        add_files -fileset constrs_1 -norecurse [file join $demo_here sensor.xdc]
        set bd [get_files ntt_system.bd]
        generate_target all $bd
        add_files [make_wrapper -files $bd -top]
        set_property top ntt_system_wrapper [get_filesets sources_1]
        update_compile_order -fileset sources_1
        if {$action eq "prepare"} {
            puts "SENSOR_PROJECT_READY=$demo_project"
            return
        }
        launch_runs impl_1 -to_step write_bitstream -jobs 8
        wait_on_run impl_1
    } else {
        if {[current_project -quiet] eq ""} {
            open_project [file join $demo_project ${demo_project_name}.xpr]
        }
        if {[file normalize [get_property DIRECTORY [current_project]]] ne [file normalize $demo_project]} {
            error "Open the sensor project in $demo_project"
        }
    }

    if {[get_property STATUS [get_runs impl_1]] ne "write_bitstream Complete!"} {
        error "Generate Bitstream did not complete"
    }
    open_run impl_1
    file mkdir $demo_output
    report_timing_summary -delay_type min_max -file [file join $demo_output i2c_timing.rpt]
    report_drc -file [file join $demo_output i2c_drc.rpt]
    set clock [get_clocks -quiet clk_pl_0]
    if {[llength $clock] != 1 || abs([get_property PERIOD $clock] - 5.0) > 0.001} {
        error "PL clock must be constrained to 200 MHz"
    }
    foreach type {max min} {
        set path [get_timing_paths -delay_type $type -max_paths 1]
        if {[llength $path] != 1 || [get_property SLACK $path] < 0} {
            error "Timing failed for delay type $type"
        }
    }
    if {[llength [get_ports -quiet {sensor_tri_io[*]}]] != 2} {
        error "Expected two sensor I2C ports"
    }
    write_hw_platform -fixed -include_bit -force -file [file join $demo_output kv260_sensor.xsa]
    file copy -force \
        [file join $demo_project ${demo_project_name}.runs impl_1 ntt_system_wrapper.bit] \
        [file join $demo_output i2c.bit]
    set init_candidates [glob -nocomplain [file join $demo_project ${demo_project_name}.gen sources_1 bd ntt_system ip * psu_init.tcl]]
    if {[llength $init_candidates] != 1} {error "Expected one generated psu_init.tcl: $init_candidates"}
    file copy -force [lindex $init_candidates 0] [file join $demo_output psu_init.tcl]
    puts "SENSOR_ARTIFACTS_READY: 200 MHz, setup/hold pass"
}

proc demo_nm {elf} {
    if {[info exists ::env(VITIS_HOME)]} {
        set nm [file join $::env(VITIS_HOME) gnu aarch64 lin aarch64-none bin aarch64-none-elf-nm]
    } else {
        set nm /home/quan/tools/Xilinx/2025.2.1/Vitis/gnu/aarch64/lin/aarch64-none/bin/aarch64-none-elf-nm
    }
    if {![file executable $nm]} {error "Missing aarch64-none-elf-nm: $nm"}
    return [exec $nm $elf]
}

proc demo_connect_and_init {} {
    global demo_output
    connect -url tcp:127.0.0.1:3121
    set targets_found [targets -target-properties -filter {name == "Cortex-A53 #0"}]
    if {[llength $targets_found] == 0} {error "KV260 Cortex-A53 target not found"}
    targets -set -filter {name == "Cortex-A53 #0"}
    if {[catch {stop} message] && ![string match {*Already stopped*} $message]} {error $message}
    rst -processor
    targets -set -filter {name == "PSU"}
    uplevel #0 [list source [demo_psu_init_path]]
    psu_init
    fpga -file [file join $demo_output i2c.bit]
    psu_ps_pl_isolation_removal
    psu_ps_pl_reset_config
    psu_post_config
    targets -set -filter {name == "Cortex-A53 #0"}
    rst -processor
}

proc demo_sensor {elf capture_dir} {
    global demo_here
    set symbols [demo_nm $elf]
    foreach name {result raw test_finished} {
        if {![regexp -line [format {^([0-9a-f]+) [BT] %s$} $name] $symbols -> address($name)]} {
            error "Missing symbol $name"
        }
    }
    demo_connect_and_init
    dow $elf
    set finish_breakpoint [bpadd -addr 0x$address(test_finished)]
    set gated [regexp -line {^([0-9a-f]+) T quality_ready$} $symbols -> ready_address]
    if {$gated} {
        if {![regexp -line {^([0-9a-f]+) B quality_approved$} $symbols -> approval_address]} {
            error "Missing quality_approved symbol"
        }
        set gate_breakpoint [bpadd -addr 0x$ready_address]
        con -block -timeout 30
        set initial [mrd -value 0x$address(result) 8]
        if {[lindex $initial 0] != 0x600D || [lindex $initial 5] != 1024 || [lindex $initial 6] != 0} {
            error "Capture did not reach quality gate safely: $initial"
        }
        set raw_all [mrd -value 0x$address(raw) 2048]
        set stream [open [file join $capture_dir quality_raw.csv] w]
        puts $stream "index,red,ir"
        for {set index 0} {$index < 1024} {incr index} {
            puts $stream "$index,[lindex $raw_all [expr {2 * $index}]],[lindex $raw_all [expr {2 * $index + 1}]]"
        }
        close $stream
        set accepted 1
        if {[catch {exec python3 -B [file join $demo_here demo.py] __quality $capture_dir} message options]} {
            set error_code [dict get $options -errorcode]
            if {[lindex $error_code 0] ne "CHILDSTATUS" || [lindex $error_code 2] != 2} {
                error "Quality analysis error: $message"
            }
            set accepted 0
        }
        puts "QUALITY_GATE_APPROVED=$accepted: $message"
        mwr 0x$approval_address $accepted
        bpremove $gate_breakpoint
    }

    con -block -timeout 30
    bpremove $finish_breakpoint
    set result [mrd -value 0x$address(result) 8]
    puts "SENSOR_RESULT=$result"
    if {$gated && [lindex $result 0] == 0x7000 && [lindex $result 6] == 0} {
        puts "QUALITY_REJECTED: NTT/INTT NOT RUN; completed_blocks=0"
        disconnect
        return
    }
    set expected_count [expr {$gated ? 1024 : 256}]
    if {[lindex $result 0] != 0x600D || [lindex $result 5] != $expected_count} {
        error "Sensor test failed: [format %X [lindex $result 0]]"
    }
    scan $address(raw) %x raw_base
    set raw_address [expr {$raw_base + ($gated ? 768 * 8 : 0)}]
    set samples [mrd -value $raw_address 512]
    set stream [open [file join $capture_dir sensor_raw.csv] w]
    puts $stream "index,red,ir"
    for {set index 0} {$index < 256} {incr index} {
        puts $stream "$index,[lindex $samples [expr {2 * $index}]],[lindex $samples [expr {2 * $index + 1}]]"
    }
    close $stream

    foreach symbol {ntt_actual packed_input intt_actual} {
        if {![regexp -line [format {^([0-9a-f]+) B %s$} $symbol] $symbols -> address($symbol)]} {
            error "Missing symbol $symbol"
        }
    }
    if {[lindex $result 6] != 4} {error "Not all four NTT blocks completed"}
    set actual [mrd -value 0x$address(ntt_actual) 1024]
    set packed [mrd -value 0x$address(packed_input) 1024]
    set stream [open [file join $capture_dir ntt_actual.csv] w]
    puts $stream "block,index,input,actual"
    for {set index 0} {$index < 1024} {incr index} {
        puts $stream "[expr {$index / 256}],[expr {$index % 256}],[lindex $packed $index],[lindex $actual $index]"
    }
    close $stream
    set inverse [mrd -value 0x$address(intt_actual) 1024]
    set stream [open [file join $capture_dir intt_actual.csv] w]
    puts $stream "index,actual"
    for {set index 0} {$index < 1024} {incr index} {puts $stream "$index,[lindex $inverse $index]"}
    close $stream
    puts "SENSOR_TO_NTT_CAPTURE_COMPLETE: host comparison still required"
    disconnect
}

proc demo_arm_test {} {
    global demo_output
    set elf [file join $demo_output test.elf]
    if {![file isfile $elf]} {error "Missing ARM test ELF: $elf"}
    set symbols [demo_nm $elf]
    if {![regexp -line {^([0-9a-f]+) B result$} $symbols -> result_address]} {error "Missing result symbol"}
    if {![regexp -line {^([0-9a-f]+) T test_finished$} $symbols -> finish_address]} {error "Missing test_finished symbol"}
    demo_connect_and_init
    dow $elf
    set breakpoint [bpadd -addr 0x$finish_address]
    con -block -timeout 30
    set values [mrd -value 0x$result_address 8]
    bpremove $breakpoint
    if {[lindex $values 0] != 0x600D || [lindex $values 5] != 768} {
        error "ARM NTT test failed: $values"
    }
    puts "ARM_NTT_HARDWARE_PASS: 3 cases, 768 coefficients"
    disconnect
}

proc demo_probe {} {
    connect -url tcp:127.0.0.1:3121
    set matches [targets -target-properties -filter {name == "Cortex-A53 #0"}]
    if {[llength $matches] == 0} {error "KV260 Cortex-A53 target not found"}
    puts "KV260_TARGET_FOUND=[llength $matches]"
    disconnect
}

if {[llength $argv] < 1} {error "Missing action: artix, build, prepare, publish, sensor, arm-test or probe"}
set action [lindex $argv 0]
if {[catch {
    switch -- $action {
        artix {
            if {[llength $argv] != 2} {error "artix requires an output directory"}
            demo_artix [lindex $argv 1]
        }
        build - prepare - publish {demo_build $action}
        sensor {
            if {[llength $argv] != 3} {error "sensor requires ELF and capture directory"}
            demo_sensor [file normalize [lindex $argv 1]] [file normalize [lindex $argv 2]]
        }
        arm-test {demo_arm_test}
        probe {demo_probe}
        default {error "Unknown action: $action"}
    }
} message options]} {
    puts stderr "FAIL: $message"
    catch {stop}
    catch {disconnect}
    return -options $options $message
}
