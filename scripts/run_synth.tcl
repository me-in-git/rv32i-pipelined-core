# Vivado non-project batch flow for rv32i_top (untested template).
# Usage (from the repo root): vivado -mode batch -source scripts/run_synth.tcl
set part  xc7a100tcsg324-1
set top   rv32i_top
set clk_p 10.0

read_verilog -sv [glob rtl/*.sv]
synth_design -top $top -part $part
create_clock -period $clk_p [get_ports clk] -name clk

opt_design
place_design
route_design

report_utilization    -file util.rpt
report_timing_summary -file timing.rpt

set wns [get_property SLACK [get_timing_paths -max_delay -nworst 1]]
set fmax_est [expr {1000.0 / ($clk_p - $wns)}]
puts "WNS: $wns ns  ->  Fmax estimate: $fmax_est MHz"
exit
