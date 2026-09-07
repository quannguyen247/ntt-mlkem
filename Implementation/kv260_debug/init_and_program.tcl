proc main {} {
    set script_dir [file normalize [file dirname [info script]]]
    set psu_init_file [file normalize [file join $script_dir project \
        ntt_kv260_debug.gen sources_1 bd ntt_kv260_debug_bd ip \
        ntt_kv260_debug_bd_ps_0_0 psu_init.tcl]]
    set bit_file [file normalize [file join $script_dir output \
        ntt_kv260_debug.bit]]

    if {![file exists $psu_init_file]} {
        error "Missing PS initialization file: $psu_init_file"
    }
    if {![file exists $bit_file]} {
        error "Missing bitstream: $bit_file"
    }

    connect
    set psu_targets [targets -target-properties -filter {name == "PSU"}]
    if {[llength $psu_targets] == 0} {
        error "KV260 PSU target was not found. Check 12 V power and micro-USB."
    }

    targets -set -filter {name == "PSU"}
    uplevel #0 [list source $psu_init_file]
    psu_init

    fpga -file $bit_file
    psu_ps_pl_isolation_removal
    psu_ps_pl_reset_config
    psu_post_config
    puts "KV260_PS_INITIALIZED_AND_BITSTREAM_PROGRAMMED"
    disconnect
}

if {[catch {main} message options]} {
    puts stderr "ERROR: $message"
    catch {disconnect}
    exit 1
}
exit 0
