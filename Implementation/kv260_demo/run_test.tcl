# XSCT -nodisp run_test.tcl. Resets A53 and replaces volatile PL configuration.
set here [file dirname [file normalize [info script]]]
proc run_test {} {
    global here
    set bit $here/project/kv260_axi_test.runs/impl_1/ntt_system_wrapper.bit
    set init $here/project/kv260_axi_test.gen/sources_1/bd/ntt_system/ip/ntt_system_ps_0/psu_init.tcl
    set elf $here/output/test.elf
    foreach f [list $bit $init $elf] {
        if {![file exists $f]} {error "Missing build artifact: $f"}
    }
    set nm /home/quan/tools/Xilinx/2025.2.1/Vitis/gnu/aarch64/lin/aarch64-none/bin/aarch64-none-elf-nm
    if {[info exists ::env(VITIS_HOME)]} {set nm $::env(VITIS_HOME)/gnu/aarch64/lin/aarch64-none/bin/aarch64-none-elf-nm}
    set symbols [exec $nm $elf]
    if {![regexp -line {^([0-9a-f]+) B result$} $symbols -> result_addr]} {error "No result symbol"}
    if {![regexp -line {^([0-9a-f]+) T test_finished$} $symbols -> finish_addr]} {error "No finish symbol"}
    connect -url tcp:127.0.0.1:3121
    targets -set -filter {name == "Cortex-A53 #0"}
    if {[catch {stop} msg] && ![string match {*Already stopped*} $msg]} {error $msg}
    rst -processor
    targets -set -filter {name == "PSU"}
    uplevel #0 [list source $init]
    psu_init
    fpga -file $bit
    psu_ps_pl_isolation_removal
    psu_ps_pl_reset_config
    psu_post_config
    targets -set -filter {name == "Cortex-A53 #0"}
    rst -processor
    dow $elf
    set bp [bpadd -addr 0x$finish_addr]
    con -block -timeout 30
    set values [mrd -value 0x$result_addr 8]
    puts "ARM_NTT_RESULT=$values"
    bpremove $bp
    if {[lindex $values 0] != 0x600D || [lindex $values 5] != 768} {
        error "ARM NTT test failed; result words: code, case, index, actual, expected, checked"
    }
    puts "ARM_NTT_HARDWARE_PASS: 3 cases, 768 coefficients compared by Cortex-A53"
    disconnect
}
if {[catch {run_test} message]} {
    puts stderr "FAIL: $message"
    catch {stop}
    catch {disconnect}
    exit 1
}
exit 0
