# Lists the distinct Zynq-7000 devices whose data is installed, so the
# license-free subset can be asserted positively rather than inferred.
set z {}
foreach p [get_parts xc7z*] {
  lappend z [regsub {(xc7z[0-9]+[a-z]*).*} $p {\1}]
}
puts "DEVICES=[lsort -unique $z]"
