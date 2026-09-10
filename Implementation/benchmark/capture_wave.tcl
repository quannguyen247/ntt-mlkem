# XSim Tcl, after elaborating tb_ntt_core_top with generated regression vectors.
puts "WAVE_SCOPES=[get_scopes]"
log_wave -r /*
add_wave /tb_ntt_core_top/clk
add_wave /tb_ntt_core_top/rst_n
add_wave /tb_ntt_core_top/start
add_wave /tb_ntt_core_top/mode
add_wave /tb_ntt_core_top/busy
add_wave /tb_ntt_core_top/done
add_wave -radix unsigned /tb_ntt_core_top/cycles
add_wave -radix unsigned /tb_ntt_core_top/dut/u_controller/len
add_wave -radix unsigned /tb_ntt_core_top/dut/u_controller/cnt
run all
save_wave_config ntt_cycles.wcfg
quit
