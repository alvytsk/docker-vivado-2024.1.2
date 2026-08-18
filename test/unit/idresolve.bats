#!/usr/bin/env bats

load helpers

setup() {
  source "$REPO_ROOT/lib/idresolve.sh"
  TMP="$(mktemp -d)"
  cat > "$TMP/passwd" <<'EOF'
root:x:0:0:root:/root:/bin/bash
nobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin
vivado:x:1000:1000:Vivado:/home/vivado:/bin/bash
EOF
  cat > "$TMP/group" <<'EOF'
root:x:0:
nogroup:x:65534:
vivado:x:1000:
EOF
}

teardown() { rm -rf "$TMP"; }

@test "ir_resolve_id prefers the explicit hint" {
  run ir_resolve_id 1234 5678 1000
  [ "$output" = "1234" ]
}

@test "ir_resolve_id falls back to the directory owner when hint is empty" {
  run ir_resolve_id "" 1234 1000
  [ "$output" = "1234" ]
}

@test "an explicit hint of 0 falls back to the default, not to the owner" {
  # An explicit HOST_UID=0 is a deliberate request for root. It is refused
  # outright rather than quietly resolving to the directory owner.
  run ir_resolve_id 0 1234 1000
  [ "$output" = "1000" ]
}

@test "ir_resolve_id treats an owner of 0 as no usable hint" {
  run ir_resolve_id "" 0 1000
  [ "$output" = "1000" ]
}

@test "ir_resolve_id falls back to default when both are empty" {
  run ir_resolve_id "" "" 1000
  [ "$output" = "1000" ]
}

@test "ir_pick_name returns vivado when the name is free at that uid" {
  run ir_pick_name 1000 "$TMP/passwd"
  [ "$output" = "vivado" ]
}

@test "ir_pick_name avoids collision with the existing vivado name" {
  run ir_pick_name 1234 "$TMP/passwd"
  [ "$output" = "vivado_1234" ]
}

@test "ir_ensure_account appends an entry for an absent uid" {
  ir_ensure_account 1234 1234 /home/vivado "$TMP/passwd" "$TMP/group"
  run grep -c '^vivado_1234:x:1234:1234:' "$TMP/passwd"
  [ "$output" = "1" ]
}

@test "ir_ensure_account leaves an existing uid untouched" {
  local before after
  before="$(cat "$TMP/passwd")"
  ir_ensure_account 65534 65534 /home/vivado "$TMP/passwd" "$TMP/group"
  after="$(cat "$TMP/passwd")"
  [ "$before" = "$after" ]
}

@test "ir_ensure_account is idempotent" {
  ir_ensure_account 1234 1234 /home/vivado "$TMP/passwd" "$TMP/group"
  ir_ensure_account 1234 1234 /home/vivado "$TMP/passwd" "$TMP/group"
  run grep -c '^vivado_1234:' "$TMP/passwd"
  [ "$output" = "1" ]
}

@test "ir_resolve_home returns the preferred dir when the prober says writable" {
  mkdir -p "$TMP/home"
  run ir_resolve_home "$TMP/home" "$TMP" test -w
  [ "$output" = "$TMP/home" ]
}

@test "ir_resolve_home falls back when the prober says not writable" {
  mkdir -p "$TMP/home"
  run ir_resolve_home "$TMP/home" "$TMP" false
  [ "$status" -eq 0 ]
  [ "$output" != "$TMP/home" ]
  [ -d "$output" ]
}

@test "ir_resolve_home never returns /root" {
  run ir_resolve_home /root "$TMP" false
  [ "$output" != "/root" ]
}
