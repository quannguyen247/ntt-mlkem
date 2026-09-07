# Separate PS -> AXI-Lite -> NTT test design; no Pmod signals driven.
set here [file dirname [file normalize [info script]]]
set impl [file dirname $here]
create_project kv260_axi_test $here/project -part xck26-sfvc784-2LV-c -force
set_property board_part xilinx.com:kv260_som:part0:1.4 [current_project]
add_files [glob $impl/rtl/modules/*.v]
add_files [glob $impl/rtl/utils/*.vh]
set_property include_dirs [list $impl/rtl/utils] [get_filesets sources_1]
create_bd_design ntt_system
set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:* ps]
apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e -config {apply_board_preset "1"} $ps
set_property -dict [list CONFIG.PSU__USE__M_AXI_GP0 {1} CONFIG.PSU__USE__M_AXI_GP1 {0} CONFIG.PSU__USE__M_AXI_GP2 {0} CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {200}] $ps
create_bd_cell -type module -reference ntt_core_axi_lite ntt
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config {Master "/ps/M_AXI_HPM0_FPD" Clk_master "/ps/pl_clk0 (200 MHz)" Clk_slave "/ps/pl_clk0 (200 MHz)" Clk_xbar "/ps/pl_clk0 (200 MHz)"} [get_bd_intf_pins ntt/s_axi]
assign_bd_address
set seg [get_bd_addr_segs -of_objects [get_bd_addr_spaces ps/Data] -filter {NAME =~ *ntt*}]
if {[llength $seg] != 1} {error "Expected one NTT address segment: $seg"}
set_property offset 0xA0000000 $seg
set_property range 4K $seg
validate_bd_design
save_bd_design
set bd [get_files ntt_system.bd]
generate_target all $bd
add_files [make_wrapper -files $bd -top]
set_property top ntt_system_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1
if {[info exists ::kv260_gui_only] && $::kv260_gui_only} {
    puts "AXI_PROJECT_READY: configure sensor via build_i2c.tcl, then use GUI runs."
    return
}
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property STATUS [get_runs impl_1]] ne "write_bitstream Complete!"} {error "Build failed"}
open_run impl_1
file mkdir $here/output
report_timing_summary -file $here/output/timing.rpt
report_drc -file $here/output/drc.rpt
set c [get_clocks clk_pl_0]
if {abs([get_property PERIOD $c]-5.0)>0.001} {error "Not 200 MHz"}
foreach type {max min} {
    set p [get_timing_paths -delay_type $type -max_paths 1]
    if {[llength $p] != 1 || [get_property SLACK $p] < 0} {error "Timing not met: $type"}
}
write_hw_platform -fixed -include_bit -force -file $here/output/kv260_axi_test.xsa
puts "AXI_BUILD_PASS"
