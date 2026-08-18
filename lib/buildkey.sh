#!/usr/bin/env bash
# Build-key computation for stage 2. Sourced, not executed.
# Docker's cache cannot see stage 2, so reuse is gated on this key.

bk_file_hash() {
  sha256sum "$1" | cut -d' ' -f1
}

bk_mode() {
  if [[ -n "${1:-}" && -f "${1:-}" ]]; then echo verified; else echo metadata; fi
}

bk_media_record() {
  local iso="$1" hashes="${2:-}" name hex
  name="$(basename "$iso")"
  if [[ ! -f "$iso" ]]; then
    echo "ERROR: media not found: $iso" >&2
    return 1
  fi
  if [[ -n "$hashes" && -f "$hashes" ]]; then
    hex="$(awk -v f="$name" '$2==f {print $1}' "$hashes")"
    if [[ -z "$hex" ]]; then
      echo "ERROR: no recorded hash for $name in $hashes" >&2
      return 1
    fi
    # Verified mode must VERIFY. Emitting the recorded hash without hashing
    # the file would make the mode a no-op: replacement or corruption would
    # still sail through, which is the exact failure it exists to catch.
    local actual
    actual="$(bk_file_hash "$iso")"
    if [[ "$actual" != "$hex" ]]; then
      echo "ERROR: ${name} sha256 mismatch: recorded ${hex}, actual ${actual}" >&2
      return 1
    fi
    printf 'media %s sha256 %s\n' "$name" "$actual"
  else
    printf 'media %s meta %s %s\n' "$name" \
      "$(stat -c%s "$iso")" "$(stat -c%Y "$iso")"
  fi
}

# bk_manifest <hashes_file_or_empty> <base_image_id> <vars> <file>...
#
# Every hash is computed into a variable and checked BEFORE it is printed.
# `printf 'file %s %s' "$f" "$(bk_file_hash "$f")"` would swallow a failed
# sha256sum entirely: printf succeeds, the field comes out empty, and the key
# is computed from a manifest with a hole in it -- which then reuses or
# rebuilds for reasons nobody can reconstruct. Assigning first keeps the
# status; `local hex` is declared separately from the assignment for the same
# reason (`local hex="$(...)"` returns local's status, not the command's).
bk_manifest() {
  local hashes="$1" base_id="$2" vars="$3"
  shift 3
  local mode f hex
  mode="$(bk_mode "$hashes")" || return 1
  printf 'mode %s\n' "$mode"
  printf 'base %s\n' "$base_id"
  printf 'vars %s\n' "$vars"
  for f in "$@"; do
    if [[ ! -f "$f" ]]; then
      echo "ERROR: build-key input missing: $f" >&2
      return 1
    fi
    hex="$(bk_file_hash "$f")" || return 1
    [[ -n "$hex" ]] || { echo "ERROR: empty hash for $f" >&2; return 1; }
    printf 'file %s %s\n' "$(basename "$f")" "$hex"
  done
}

bk_key() {
  sha256sum | cut -d' ' -f1
}
