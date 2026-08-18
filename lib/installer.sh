#!/usr/bin/env bash
# The ONE recorded form of each installer invocation, from
# docs/installer-facts.md. Sourced by container-install.sh and add-vitis.sh.
# Never inline these commands anywhere else.

# An ARRAY, not a string: `$XSETUP_EULA` unquoted is SC2086 and `make lint`
# is required to pass with no warnings, so a scalar here would fail the build
# before it ever reached the installer.
# The element is quoted only to silence SC2054 (ShellCheck reads the comma as
# a separator); the argv is identical either way, and installer.bats proves it.
XSETUP_EULA=(-a "XilinxEULA,3rdPartyEULA")

xsetup_install() { local x="$1" cfg="$2"; "$x" "${XSETUP_EULA[@]}" -b Install -c "$cfg"; }
xsetup_add()     { local x="$1" cfg="$2"; "$x" "${XSETUP_EULA[@]}" -b Add     -c "$cfg"; }
# ADJUST THIS LINE to the form recorded in Task 2, if it is not -c.
xsetup_update()  { local x="$1" cfg="$2"; "$x" "${XSETUP_EULA[@]}" -b Update  -c "$cfg"; }
