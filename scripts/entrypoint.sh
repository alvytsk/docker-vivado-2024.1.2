#!/usr/bin/env bash
set -euo pipefail

IR_LIB="${IR_LIB:-/usr/local/lib/idresolve.sh}"
VIVADO_SETTINGS="${VIVADO_SETTINGS:-/tools/Xilinx/Vivado/2024.1/settings64.sh}"
# Absent from the default image, present in the Vitis variant. Having the file
# on disk is not what puts xsct on PATH -- sourcing it is. AMD's 2024.1 setup
# instructions require it, and the variant's tests invoke xsct directly.
VITIS_SETTINGS="${VITIS_SETTINGS:-/tools/Xilinx/Vitis/2024.1/settings64.sh}"
PASSWD_FILE="${PASSWD_FILE:-/etc/passwd}"
GROUP_FILE="${GROUP_FILE:-/etc/group}"
GOSU="${GOSU:-gosu}"
WORK_DIR="${WORK_DIR:-/work}"
HOME_DIR="${HOME_DIR:-/home/vivado}"

# shellcheck source=/dev/null
source "$IR_LIB"

# One definition, used by both identity branches. Duplicating these two lines
# is how the --user path and the gosu path end up with different environments.
source_tool_settings() {
  # shellcheck source=/dev/null
  [[ -f "$VIVADO_SETTINGS" ]] && source "$VIVADO_SETTINGS"
  # Vitis AFTER Vivado: it appends to PATH rather than replacing it, and the
  # variant must keep XILINX_VIVADO pointing at the Vivado install.
  # shellcheck source=/dev/null
  [[ -f "$VITIS_SETTINGS" ]] && source "$VITIS_SETTINGS"
  return 0   # a missing optional file is not a failure
}

effective_uid="${FAKE_EUID:-$(id -u)}"

if [[ "$effective_uid" != "0" ]]; then
  # Started with --user. We cannot edit /etc/passwd and do not need to;
  # gosu is unnecessary. HOME is still set explicitly, never inherited.
  export HOME
  HOME="$(ir_resolve_home "$HOME_DIR" /tmp test -w)"
  source_tool_settings
  exec "$@"
fi

work_uid=""; work_gid=""
if [[ -d "$WORK_DIR" ]]; then
  work_uid="$(stat -c%u "$WORK_DIR")"
  work_gid="$(stat -c%g "$WORK_DIR")"
fi

uid="$(ir_resolve_id "${HOST_UID:-}" "$work_uid" 1000)"
gid="$(ir_resolve_id "${HOST_GID:-}" "$work_gid" 1000)"

ir_ensure_account "$uid" "$gid" "$HOME_DIR" "$PASSWD_FILE" "$GROUP_FILE"

# Judge writability AS THE TARGET USER. As root every path looks writable.
export HOME
HOME="$(ir_resolve_home "$HOME_DIR" /tmp "$GOSU" "${uid}:${gid}" test -w)"

source_tool_settings

exec "$GOSU" "${uid}:${gid}" "$@"
