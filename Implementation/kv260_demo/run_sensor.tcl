set here [file dirname [file normalize [info script]]]
set sensor_elf $here/output/sensor.elf
set capture_dir $here/output
if {[llength $argv]>0} {set sensor_elf [lindex $argv 0]}
if {[llength $argv]>1} {set capture_dir [lindex $argv 1]}
proc test_sensor {} {
 global here sensor_elf capture_dir
 set nm /home/quan/tools/Xilinx/2025.2.1/Vitis/gnu/aarch64/lin/aarch64-none/bin/aarch64-none-elf-nm
 if {[info exists ::env(VITIS_HOME)]} {set nm $::env(VITIS_HOME)/gnu/aarch64/lin/aarch64-none/bin/aarch64-none-elf-nm}
 set syms [exec $nm $sensor_elf]
 foreach name {result raw test_finished} {
  if {![regexp -line [format {^([0-9a-f]+) [BT] %s$} $name] $syms -> addr($name)]} {error "Missing $name"}
 }
 connect -url tcp:127.0.0.1:3121
 targets -set -filter {name == "Cortex-A53 #0"}
 if {[catch {stop} msg] && ![string match {*Already stopped*} $msg]} {error $msg}
 rst -processor
 targets -set -filter {name == "PSU"}
 uplevel #0 [list source $here/project/kv260_axi_test.gen/sources_1/bd/ntt_system/ip/ntt_system_ps_0/psu_init.tcl]
 psu_init
 fpga -file $here/output/i2c.bit
 psu_ps_pl_isolation_removal
 psu_ps_pl_reset_config
 psu_post_config
 targets -set -filter {name == "Cortex-A53 #0"}
 rst -processor
 dow $sensor_elf
 set bp [bpadd -addr 0x$addr(test_finished)]
 set gated [regexp -line {^([0-9a-f]+) T quality_ready$} $syms -> ready_addr]
 if {$gated} {
  if {![regexp -line {^([0-9a-f]+) B quality_approved$} $syms -> approval_addr]} {error "Missing quality gate"}
  set gatebp [bpadd -addr 0x$ready_addr]
  con -block -timeout 30
  set initial [mrd -value 0x$addr(result) 8]
  if {[lindex $initial 0]!=0x600D || [lindex $initial 5]!=1024 || [lindex $initial 6]!=0} {error "Capture did not reach gate safely: $initial"}
  set raw_all [mrd -value 0x$addr(raw) 2048]
  set f [open $capture_dir/quality_raw.csv w]
  puts $f "index,red,ir"
  for {set i 0} {$i<1024} {incr i} {puts $f "$i,[lindex $raw_all [expr 2*$i]],[lindex $raw_all [expr 2*$i+1]]"}
  close $f
  set accepted 1
  if {[catch {exec python3 -B $here/ppg_quality.py $capture_dir} message options]} {
   set ec [dict get $options -errorcode]
   if {[lindex $ec 0] ne "CHILDSTATUS" || [lindex $ec 2]!=2} {error "Quality analysis error: $message"}
   set accepted 0
  }
  puts "QUALITY_GATE_APPROVED=$accepted: $message"
  mwr 0x$approval_addr $accepted
  bpremove $gatebp
 }
 con -block -timeout 30
 bpremove $bp
 set r [mrd -value 0x$addr(result) 8]
 puts "SENSOR_RESULT=$r"
 if {$gated && [lindex $r 0]==0x7000 && [lindex $r 6]==0} {
  puts "QUALITY_REJECTED: NTT/INTT NOT RUN; completed_blocks=0"
  disconnect
  return
 }
 set expected_count [expr {$gated ? 1024 : 256}]
 if {[lindex $r 0]!=0x600D || [lindex $r 5]!=$expected_count} {error "Sensor test failed: [format %X [lindex $r 0]]"}
 set raw_address [expr 0x$addr(raw) + ($gated ? 768*8 : 0)]
 set samples [mrd -value $raw_address 512]
 set f [open $capture_dir/sensor_raw.csv w]
 puts $f "index,red,ir"
 for {set i 0} {$i<256} {incr i} {puts $f "$i,[lindex $samples [expr 2*$i]],[lindex $samples [expr 2*$i+1]]"}
 close $f
 if {[regexp -line {^([0-9a-f]+) B ntt_actual$} $syms -> actual_addr]} {
  if {[lindex $r 6]!=4} {error "Not all NTT blocks completed"}
  if {![regexp -line {^([0-9a-f]+) B packed_input$} $syms -> packed_addr]} {error "No packed_input symbol"}
  set actual [mrd -value 0x$actual_addr 1024]
  set packed [mrd -value 0x$packed_addr 1024]
  set f [open $capture_dir/ntt_actual.csv w]
  puts $f "block,index,input,actual"
  for {set i 0} {$i<1024} {incr i} {puts $f "[expr $i/256],[expr $i%256],[lindex $packed $i],[lindex $actual $i]"}
  close $f
  if {![regexp -line {^([0-9a-f]+) B intt_actual$} $syms -> inverse_addr]} {error "No INTT output"}
  set inverse [mrd -value 0x$inverse_addr 1024]
  set f [open $capture_dir/intt_actual.csv w]
  puts $f "index,actual"
  for {set i 0} {$i<1024} {incr i} {puts $f "$i,[lindex $inverse $i]"}
  close $f
  puts "SENSOR_TO_NTT_CAPTURE_COMPLETE: reference comparison still required"
 }
 puts "SENSOR_FIFO_READ_PASS: 256 red/IR pairs saved; optical quality not yet verified"
 disconnect
}
if {[catch {test_sensor} msg]} {puts stderr "FAIL: $msg";catch {stop};catch {disconnect};exit 1}
exit 0
