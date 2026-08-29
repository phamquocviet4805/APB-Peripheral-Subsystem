read_liberty lib/NangateOpenCellLibrary_typical.lib

read_verilog build/apb_subsystem_mapped.v

link_design apb_subsystem

read_sdc constraints/apb_subsystem.sdc


puts ""
puts "========== SETUP CHECK =========="
report_checks -path_delay max -group_count 5

puts ""
puts "========== HOLD CHECK =========="
report_checks -path_delay min -group_count 5

puts ""
puts "========== SUMMARY =========="
report_wns
report_tns

exit