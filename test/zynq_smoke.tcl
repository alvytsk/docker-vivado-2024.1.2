# Minimal XC7Z020 BLOCK DESIGN with a real Zynq processing system.
#
# An RTL-only design would not prove what CI depends on: that
# processing_system7 elaborates, that block automation runs, that wrapper
# generation works, and that write_hw_platform can emit a PS handoff. A
# PS-only BD is deliberately chosen -- FIXED_IO and DDR use dedicated pins,
# so it needs no I/O constraints and cannot fail on unconstrained-pin DRCs.

set part   [expr {[info exists ::env(SMOKE_PART)] ? $::env(SMOKE_PART) : "xc7z020clg484-1"}]
set jobs   [expr {[info exists ::env(SMOKE_JOBS)] ? $::env(SMOKE_JOBS) : 4}]
set outdir /work/smoke_out
file delete -force $outdir
file mkdir $outdir

create_project smoke $outdir -part $part -force

create_bd_design "system"
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7 ps7_0
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
  -config {make_external "FIXED_IO, DDR" apply_board_preset "0" \
           Master "Disable" Slave "Disable"} [get_bd_cells ps7_0]

validate_bd_design
save_bd_design

set bd [get_files system.bd]
generate_target all $bd
make_wrapper -files $bd -top

# The generated wrapper path moved in 2020.2+; glob rather than hardcode.
set wrapper [lindex [glob -nocomplain $outdir/smoke.gen/sources_1/bd/system/hdl/system_wrapper.v] 0]
if {$wrapper eq ""} {
  set wrapper [lindex [glob $outdir/smoke.srcs/sources_1/bd/system/hdl/system_wrapper.v] 0]
}
add_files -norecurse $wrapper
set_property top system_wrapper [current_fileset]
update_compile_order -fileset sources_1

launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
  error "SMOKE_FAIL: synthesis did not complete"
}

launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
  error "SMOKE_FAIL: implementation did not complete"
}

set bit $outdir/smoke.runs/impl_1/system_wrapper.bit
if {![file exists $bit]} { error "SMOKE_FAIL: no bitstream at $bit" }
file copy -force $bit /work/smoke.bit

open_run impl_1
set_property platform.default_output_type "SD_CARD" [current_project]
write_hw_platform -fixed -include_bit -force /work/smoke.xsa

puts "SMOKE_OK"
