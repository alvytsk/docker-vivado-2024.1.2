#!/usr/bin/env bats

load helpers

CFG() { echo "$REPO_ROOT/config/install_config.vivado.txt"; }

@test "config: installs Vivado ML Standard to /tools/Xilinx" {
  run grep -x 'Edition=Vivado ML Standard' "$(CFG)"
  [ "$status" -eq 0 ]
  run grep -x 'Product=Vivado' "$(CFG)"
  [ "$status" -eq 0 ]
  run grep -x 'Destination=/tools/Xilinx' "$(CFG)"
  [ "$status" -eq 0 ]
}

@test "config: Zynq-7000 is the only selected device family" {
  local modules selected
  modules="$(grep '^Modules=' "$(CFG)" | sed 's/^Modules=//')"
  selected="$(echo "$modules" | tr ',' '\n' | grep ':1$' | sed 's/:1$//')"
  [ "$selected" = "Zynq-7000" ]
}

@test "config: docnav and model composer are deselected" {
  run grep -q 'DocNav:0' "$(CFG)"
  [ "$status" -eq 0 ]
  run grep -q 'Vitis Model Composer' "$(CFG)"
  [ "$status" -eq 0 ]
  run bash -c "grep -o 'Vitis Model Composer[^,]*' '$(CFG)' | grep -q ':0$'"
  [ "$status" -eq 0 ]
}

@test "config: vitis embedded development is deselected by default" {
  run grep -q 'Vitis Embedded Development:0' "$(CFG)"
  [ "$status" -eq 0 ]
}

@test "config: all shortcut and file-association options are off" {
  for k in CreateProgramGroupShortcuts CreateShortcutsForAllUsers CreateDesktopShortcuts CreateFileAssociation; do
    run grep -x "$k=0" "$(CFG)"
    [ "$status" -eq 0 ]
  done
}

@test "config: contains no license directive" {
  run grep -iE 'licen[sc]e|\.lic' "$(CFG)"
  [ "$status" -ne 0 ]
}
