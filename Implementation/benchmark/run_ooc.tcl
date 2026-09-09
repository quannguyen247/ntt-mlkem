# Run from Vivado: vivado -mode batch -source run_ooc.tcl -tclargs OUTPUT_DIR
# Standalone core benchmark, not a board bitstream. Same recipe for each variant.
set root [file normalize [file join [file dirname [info script]] ../..]]
if {$argc < 1 || $argc > 2} {error "Usage: run_ooc.tcl OUTPUT_DIR ?SYNTH_DIRECTIVE?"}
set directive Default
if {$argc == 2} {set directive [lindex $argv 1]}
set out [file normalize [lindex $argv 0]]
file mkdir $out
cd $out
set_param general.maxThreads 4
create_project -in_memory -part xc7a100tfgg676-3
set_property include_dirs [list $root/Implementation/rtl/utils] [current_fileset]
foreach name {ntt_agu ntt_butterfly ntt_controller ntt_core_top ntt_mod_mul_12b ntt_ram_dual ntt_twiddle_rom} {
    read_verilog $root/Implementation/rtl/modules/$name.v
}
read_xdc $root/Implementation/constraint/ntt.xdc
synth_design -top ntt_core_top -part xc7a100tfgg676-3 -mode out_of_context -max_dsp 0 -directive $directive
opt_design
place_design
phys_opt_design
route_design
report_timing_summary -delay_type min_max -report_unconstrained -file $out/timing.rpt
report_utilization -hierarchical -file $out/utilization_hier.rpt
report_utilization -file $out/utilization.rpt
report_drc -file $out/drc.rpt
report_route_status -file $out/route.rpt
report_power -file $out/power_vectorless.rpt
write_checkpoint -force $out/routed.dcp
write_verilog -force -mode funcsim $out/routed.v
puts "BENCHMARK_FINISHED $out"
