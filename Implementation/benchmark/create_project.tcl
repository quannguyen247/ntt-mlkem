# Creates a separate GUI project. Never overwrites Implementation/NTT.xpr.
set here [file normalize [file dirname [info script]]]
set root [file normalize $here/../..]
set out $root/build/ppa/vivado
if {$argc > 0} {set out [file normalize [lindex $argv 0]]}
# Vivado 2025.2.1 reports an empty board as missing even for new part-only
# projects. Reclassify ONLY the empty-board message; named-board failures remain.
set_msg_config -id {Project 1-5713} -string {Board part ''} -new_severity INFO
create_project ntt_artix200 $out -part xc7a100tfgg676-3
set_property include_dirs [list $root/Implementation/rtl/utils] [current_fileset]
foreach name {ntt_agu ntt_butterfly ntt_controller ntt_core_top ntt_mod_mul_12b ntt_ram_dual ntt_twiddle_rom} {
    add_files $root/Implementation/rtl/modules/$name.v
}
add_files -fileset constrs_1 $root/Implementation/constraint/ntt.xdc
set_property top ntt_core_top [current_fileset]
set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} -value {-mode out_of_context} -objects [get_runs synth_1]
set_property strategy {Vivado Synthesis Defaults} [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.MAX_DSP 0 [get_runs synth_1]
set_property strategy {Vivado Implementation Defaults} [get_runs impl_1]
update_compile_order -fileset sources_1
add_files -fileset sim_1 $root/Implementation/testbench/tb_ntt_core_top.sv
set_property top tb_ntt_core_top [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
set_property -name xsim.simulate.xsim.more_options -value [list -testplusarg "VEC_DIR=$root/build/ppa/vectors"] -objects [get_filesets sim_1]
puts "OPEN_GUI_PROJECT $out/ntt_artix200.xpr"
