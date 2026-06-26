puts "Searching installed Zynq-7000 parts..."
set zynq_parts [get_parts *xc7z*]
foreach p $zynq_parts {
  puts $p
}
puts "Total Zynq parts: [llength $zynq_parts]"

puts ""
puts "Searching installed xc7 parts..."
set xc7_parts [get_parts *xc7*]
foreach p [lrange $xc7_parts 0 100] {
  puts $p
}
puts "Total xc7 parts: [llength $xc7_parts]"
