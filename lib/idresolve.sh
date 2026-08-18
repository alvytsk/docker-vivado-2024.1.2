#!/usr/bin/env bash
# Runtime identity reconciliation. Sourced, not executed.
#
# Two rules encoded here, both from spec review:
#   - A resolved id of 0 is "no usable hint", never an instruction. Without
#     this, an unmounted or root-owned /work remaps the user to root.
#   - Never usermod/groupmod. Those fail when the target id already exists
#     (65534 vs nobody). Append a record instead, and only when absent.

# Semantics, chosen deliberately:
#   explicit hint, non-zero  -> use it
#   explicit hint of 0       -> refuse, use the fallback. An explicit request
#                               for root is denied outright; silently using the
#                               directory owner instead would be surprising.
#   no hint, owner non-zero  -> infer from the directory owner
#   no hint, owner 0 or none -> fallback
ir_resolve_id() {
  local hint="${1:-}" owner="${2:-}" fallback="$3"
  if [[ -n "$hint" ]]; then
    if [[ "$hint" == "0" ]]; then printf '%s\n' "$fallback"; else printf '%s\n' "$hint"; fi
    return 0
  fi
  if [[ -n "$owner" && "$owner" != "0" ]]; then
    printf '%s\n' "$owner"
  else
    printf '%s\n' "$fallback"
  fi
}

ir_pick_name() {
  local uid="$1" pw="$2"
  # "vivado" is usable if it is unused, OR if it already belongs to this uid.
  # Checking only "is the name present" would rename the stock 1000 account.
  if awk -F: -v n=vivado -v u="$uid" '$1==n && $3!=u {taken=1} END {exit !taken}' "$pw"; then
    printf 'vivado_%s\n' "$uid"
  else
    printf 'vivado\n'
  fi
}

ir_ensure_account() {
  local uid="$1" gid="$2" home="$3" pw="$4" gr="$5" name
  if ! awk -F: -v g="$gid" '$3==g {found=1} END {exit !found}' "$gr"; then
    printf 'vivado_%s:x:%s:\n' "$gid" "$gid" >> "$gr"
  fi
  if ! awk -F: -v u="$uid" '$3==u {found=1} END {exit !found}' "$pw"; then
    name="$(ir_pick_name "$uid" "$pw")"
    printf '%s:x:%s:%s:Vivado:%s:/bin/bash\n' "$name" "$uid" "$gid" "$home" >> "$pw"
  fi
}

# ir_resolve_home <preferred> <fallback_base> <prober...>
# The prober is invoked as: <prober...> <dir>. In the container it is
# `gosu <uid>:<gid> test -w`, so writability is judged as the TARGET user --
# testing as root would always succeed and defeat the check.
ir_resolve_home() {
  local preferred="$1" fallback_base="$2"
  shift 2
  local d
  if [[ -d "$preferred" ]] && "$@" "$preferred"; then
    printf '%s\n' "$preferred"
    return 0
  fi
  d="$(mktemp -d "${fallback_base}/vivado-home.XXXXXX")"
  chmod 0777 "$d"
  printf '%s\n' "$d"
}
