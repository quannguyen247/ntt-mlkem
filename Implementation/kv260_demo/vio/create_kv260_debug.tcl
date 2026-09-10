set script_dir [file normalize [file dirname [info script]]]
set impl_dir [file normalize [file join $script_dir .. ..]]
set project_dir [file normalize [file join $script_dir project]]
set output_dir [file normalize [file join $script_dir output]]

file mkdir $project_dir
file mkdir $output_dir

create_project ntt_kv260_debug $project_dir -force \
    -part xck26-sfvc784-2LV-c
set_property board_part xilinx.com:kv260_som:part0:1.4 [current_project]
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set rtl_files [list \
    [file join $impl_dir rtl utils ntt_defs.vh] \
    [file join $impl_dir rtl utils ntt_funcs.vh] \
    [file join $impl_dir rtl modules ntt_agu.v] \
    [file join $impl_dir rtl modules ntt_butterfly.v] \
    [file join $impl_dir rtl modules ntt_controller.v] \
    [file join $impl_dir rtl modules ntt_mod_mul_12b.v] \
    [file join $impl_dir rtl modules ntt_ram_dual.v] \
    [file join $impl_dir rtl modules ntt_twiddle_rom.v] \
    [file join $impl_dir rtl modules ntt_core_top.v] \
    [file join $script_dir rtl ntt_kv260_debug_bridge.v]]

add_files -norecurse $rtl_files
set_property include_dirs [list \
    [file join $impl_dir rtl utils] \
    [file join $impl_dir rtl modules]] [get_filesets sources_1]

add_files -fileset constrs_1 -norecurse \
    [file join $script_dir constraint kv260_debug.xdc]

create_bd_design ntt_kv260_debug_bd

set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:* ps_0]
apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e \
    -config {apply_board_preset "1"} $ps

# Only PL clock/reset are needed for this JTAG/VIO bring-up design.
# The on-board debug build is required to run the NTT core at 200 MHz.
set_property -dict [list \
    CONFIG.PSU__USE__M_AXI_GP0 {0} \
    CONFIG.PSU__USE__M_AXI_GP1 {0} \
    CONFIG.PSU__USE__M_AXI_GP2 {0} \
    CONFIG.PSU__USE__IRQ0 {0} \
    CONFIG.PSU__FPGA_PL0_ENABLE {1} \
    CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {200} \
    CONFIG.PSU__PL_CLK0_BUF {TRUE}] $ps

set bridge [create_bd_cell -type module \
    -reference ntt_kv260_debug_bridge ntt_debug_0]

set vio [create_bd_cell -type ip -vlnv xilinx.com:ip:vio:* vio_0]
set_property -dict [list \
    CONFIG.C_NUM_PROBE_IN {4} \
    CONFIG.C_NUM_PROBE_OUT {6} \
    CONFIG.C_PROBE_IN0_WIDTH {12} \
    CONFIG.C_PROBE_IN1_WIDTH {1} \
    CONFIG.C_PROBE_IN2_WIDTH {1} \
    CONFIG.C_PROBE_IN3_WIDTH {1} \
    CONFIG.C_PROBE_OUT0_WIDTH {1} \
    CONFIG.C_PROBE_OUT1_WIDTH {1} \
    CONFIG.C_PROBE_OUT2_WIDTH {1} \
    CONFIG.C_PROBE_OUT3_WIDTH {1} \
    CONFIG.C_PROBE_OUT4_WIDTH {8} \
    CONFIG.C_PROBE_OUT5_WIDTH {12} \
    CONFIG.C_PROBE_OUT0_INIT_VAL {0x0} \
    CONFIG.C_PROBE_OUT1_INIT_VAL {0x0} \
    CONFIG.C_PROBE_OUT2_INIT_VAL {0x0} \
    CONFIG.C_PROBE_OUT3_INIT_VAL {0x0} \
    CONFIG.C_PROBE_OUT4_INIT_VAL {0x00} \
    CONFIG.C_PROBE_OUT5_INIT_VAL {0x000}] $vio

connect_bd_net [get_bd_pins ps_0/pl_clk0] \
    [get_bd_pins ntt_debug_0/clk] \
    [get_bd_pins vio_0/clk]
connect_bd_net [get_bd_pins ps_0/pl_resetn0] \
    [get_bd_pins ntt_debug_0/ps_resetn]

connect_bd_net [get_bd_pins vio_0/probe_out0] \
    [get_bd_pins ntt_debug_0/vio_resetn]
connect_bd_net [get_bd_pins vio_0/probe_out1] \
    [get_bd_pins ntt_debug_0/start]
connect_bd_net [get_bd_pins vio_0/probe_out2] \
    [get_bd_pins ntt_debug_0/mode]
connect_bd_net [get_bd_pins vio_0/probe_out3] \
    [get_bd_pins ntt_debug_0/ext_we]
connect_bd_net [get_bd_pins vio_0/probe_out4] \
    [get_bd_pins ntt_debug_0/ext_addr]
connect_bd_net [get_bd_pins vio_0/probe_out5] \
    [get_bd_pins ntt_debug_0/ext_din]

connect_bd_net [get_bd_pins ntt_debug_0/ext_dout] \
    [get_bd_pins vio_0/probe_in0]
connect_bd_net [get_bd_pins ntt_debug_0/busy] \
    [get_bd_pins vio_0/probe_in1]
connect_bd_net [get_bd_pins ntt_debug_0/done] \
    [get_bd_pins vio_0/probe_in2]
connect_bd_net [get_bd_pins ntt_debug_0/done_sticky] \
    [get_bd_pins vio_0/probe_in3]

validate_bd_design
save_bd_design

set bd_file [get_files ntt_kv260_debug_bd.bd]
generate_target all $bd_file
make_wrapper -files $bd_file -top
set wrapper_file [file join $project_dir ntt_kv260_debug.gen sources_1 \
    bd ntt_kv260_debug_bd hdl ntt_kv260_debug_bd_wrapper.v]
add_files -norecurse $wrapper_file
set_property top ntt_kv260_debug_bd_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1

set_property strategy Flow_PerfOptimized_high [get_runs synth_1]
set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]

# Set ::kv260_gui_only before sourcing to keep the project open for GUI use.
if {[info exists ::kv260_gui_only] && $::kv260_gui_only} {
    puts "KV260_PROJECT_READY: run synthesis and implementation in the GUI."
    return
}

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

if {[get_property STATUS [get_runs impl_1]] ne "write_bitstream Complete!"} {
    puts "ERROR: Implementation did not complete."
    puts "STATUS: [get_property STATUS [get_runs impl_1]]"
    exit 1
}

open_run impl_1

# Refuse to publish a bitstream unless the implemented PL clock is constrained
# to exactly 5.000 ns (200 MHz). The PS IP creates this clock constraint.
set pl_clock [get_clocks -quiet clk_pl_0]
if {[llength $pl_clock] != 1} {
    error "Expected exactly one clk_pl_0 clock, found [llength $pl_clock]."
}
set pl_period [get_property PERIOD $pl_clock]
if {abs($pl_period - 5.000) > 0.001} {
    error "KV260 PL clock constraint must be 5.000 ns (200 MHz), got $pl_period ns."
}

report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -max_paths 10 -input_pins \
    -file [file join $output_dir timing_summary.rpt]
report_utilization -file [file join $output_dir utilization.rpt]
report_drc -file [file join $output_dir drc.rpt]

set bit_file [file join $project_dir ntt_kv260_debug.runs impl_1 \
    ntt_kv260_debug_bd_wrapper.bit]
set ltx_file [file join $project_dir ntt_kv260_debug.runs impl_1 \
    ntt_kv260_debug_bd_wrapper.ltx]

file copy -force $bit_file [file join $output_dir ntt_kv260_debug.bit]
if {[file exists $ltx_file]} {
    file copy -force $ltx_file [file join $output_dir ntt_kv260_debug.ltx]
}

write_hw_platform -fixed -include_bit -force \
    -file [file join $output_dir ntt_kv260_debug.xsa]

puts "KV260_DEBUG_BUILD_COMPLETE"
puts "BITSTREAM=[file join $output_dir ntt_kv260_debug.bit]"
puts "XSA=[file join $output_dir ntt_kv260_debug.xsa]"
close_project
exit
