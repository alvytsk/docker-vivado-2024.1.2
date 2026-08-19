# Answers one question: is the part DATA for a given part installed?
# Deliberately says nothing about licensing -- device-scope.bats separates
# "the part is not there" from "the part is there but needs a license", and
# this file is the "is it there" half.
set part [expr {[info exists ::env(PROBE_PART)] ? $::env(PROBE_PART) : "xc7z045ffg900-2"}]
puts "PARTS=[llength [get_parts $part]]"
