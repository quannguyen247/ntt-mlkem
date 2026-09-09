set out [file normalize [lindex $argv 0]]
cd $out
open_checkpoint $out/routed.dcp
read_saif -strip_path tb_ntt_core_top/dut $out/simulation/activity.saif
report_power -file $out/power_saif.rpt
