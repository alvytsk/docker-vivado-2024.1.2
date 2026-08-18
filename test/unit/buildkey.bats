#!/usr/bin/env bats

load helpers

setup() {
  source "$REPO_ROOT/lib/buildkey.sh"
  TMP="$(mktemp -d)"
  printf 'iso-content' > "$TMP/base.iso"
  printf 'config-content' > "$TMP/cfg.txt"
}

teardown() { rm -rf "$TMP"; }

@test "bk_file_hash returns a 64-char sha256" {
  run bk_file_hash "$TMP/cfg.txt"
  [ "$status" -eq 0 ]
  [ "${#output}" -eq 64 ]
}

@test "bk_media_record uses size and mtime when no hashes file" {
  run bk_media_record "$TMP/base.iso"
  [ "$status" -eq 0 ]
  [[ "$output" == "media base.iso meta 11 "* ]]
}

@test "verified mode hashes the ISO and accepts a matching record" {
  local real
  real="$(sha256sum "$TMP/base.iso" | cut -d' ' -f1)"
  echo "$real  base.iso" > "$TMP/media.sha256"
  run bk_media_record "$TMP/base.iso" "$TMP/media.sha256"
  [ "$status" -eq 0 ]
  [ "$output" = "media base.iso sha256 $real" ]
}

@test "verified mode FAILS when the ISO content does not match the record" {
  # The whole point of verified mode. A record that is merely read back
  # without hashing would let corruption through silently.
  echo "deadbeef  base.iso" > "$TMP/media.sha256"
  run bk_media_record "$TMP/base.iso" "$TMP/media.sha256"
  [ "$status" -ne 0 ]
  [[ "$output" == *"mismatch"* ]]
}

@test "verified mode detects content changing under a stable record" {
  local real
  real="$(sha256sum "$TMP/base.iso" | cut -d' ' -f1)"
  echo "$real  base.iso" > "$TMP/media.sha256"
  printf 'tampered' > "$TMP/base.iso"
  run bk_media_record "$TMP/base.iso" "$TMP/media.sha256"
  [ "$status" -ne 0 ]
}

@test "bk_media_record fails loudly when the ISO is missing" {
  run bk_media_record "$TMP/absent.iso"
  [ "$status" -ne 0 ]
  [[ "$output" == *"absent.iso"* ]]
}

@test "bk_media_record fails when hashes file lacks an entry for the ISO" {
  echo "deadbeef  other.iso" > "$TMP/media.sha256"
  run bk_media_record "$TMP/base.iso" "$TMP/media.sha256"
  [ "$status" -ne 0 ]
}

@test "bk_mode reports metadata or verified" {
  run bk_mode "$TMP/nope"
  [ "$output" = "metadata" ]
  touch "$TMP/media.sha256"
  run bk_mode "$TMP/media.sha256"
  [ "$output" = "verified" ]
}

@test "bk_manifest FAILS on a missing input instead of emitting an empty hash" {
  run bk_manifest "" "sha256:abc123" "V=1" "$TMP/cfg.txt" "$TMP/nope.txt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"nope.txt"* ]]
}

@test "bk_manifest includes mode, base image id, vars and every file hash" {
  run bk_manifest "" "sha256:abc123" "MEDIA=/x DEST=/tools/Xilinx" "$TMP/cfg.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"mode metadata"* ]]
  [[ "$output" == *"base sha256:abc123"* ]]
  [[ "$output" == *"vars MEDIA=/x DEST=/tools/Xilinx"* ]]
  [[ "$output" == *"file cfg.txt "* ]]
}

@test "bk_key changes when any input changes" {
  local k1 k2
  k1="$(bk_manifest "" "id1" "V=1" "$TMP/cfg.txt" | bk_key)"
  printf 'changed' > "$TMP/cfg.txt"
  k2="$(bk_manifest "" "id1" "V=1" "$TMP/cfg.txt" | bk_key)"
  [ "$k1" != "$k2" ]
}

@test "bk_key is stable for identical inputs" {
  local k1 k2
  k1="$(bk_manifest "" "id1" "V=1" "$TMP/cfg.txt" | bk_key)"
  k2="$(bk_manifest "" "id1" "V=1" "$TMP/cfg.txt" | bk_key)"
  [ "$k1" = "$k2" ]
}

@test "bk_key changes when the base image id changes" {
  local k1 k2
  k1="$(bk_manifest "" "id1" "V=1" "$TMP/cfg.txt" | bk_key)"
  k2="$(bk_manifest "" "id2" "V=1" "$TMP/cfg.txt" | bk_key)"
  [ "$k1" != "$k2" ]
}
