#!/usr/bin/env bats

load helpers

setup() {
  TMP="$(mktemp -d)"
  mkdir -p "$TMP/work" "$TMP/home" "$TMP/bin"
  cat > "$TMP/passwd" <<'EOF'
root:x:0:0:root:/root:/bin/bash
vivado:x:1000:1000:Vivado:/home/vivado:/bin/bash
EOF
  echo 'vivado:x:1000:' > "$TMP/group"
  : > "$TMP/settings.sh"
  : > "$TMP/vitis-settings.sh"
  # Fake gosu: record the ids it was asked for, then run the command.
  cat > "$TMP/bin/gosu" <<'EOF'
#!/usr/bin/env bash
echo "$1" > "$GOSU_LOG"
shift
exec "$@"
EOF
  chmod +x "$TMP/bin/gosu"
  export GOSU_LOG="$TMP/gosu.log"
}

teardown() { rm -rf "$TMP"; }

run_ep() {
  IR_LIB="$REPO_ROOT/lib/idresolve.sh" \
  VIVADO_SETTINGS="$TMP/settings.sh" \
  VITIS_SETTINGS="${VITIS_SETTINGS:-$TMP/vitis-settings.sh}" \
  PASSWD_FILE="$TMP/passwd" GROUP_FILE="$TMP/group" \
  GOSU="$TMP/bin/gosu" WORK_DIR="$TMP/work" HOME_DIR="$TMP/home" \
  FAKE_EUID="${FAKE_EUID:-0}" \
  run bash "$REPO_ROOT/scripts/entrypoint.sh" "$@"
}

@test "entrypoint sets HOME explicitly and never leaks /root" {
  HOME=/root run_ep bash -c 'echo "HOME=$HOME"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"HOME=$TMP/home"* ]]
  [[ "$output" != *"HOME=/root"* ]]
}

@test "entrypoint drops to the HOST_UID when given" {
  HOST_UID=1234 HOST_GID=1234 run_ep true
  [ "$status" -eq 0 ]
  [ "$(cat "$GOSU_LOG")" = "1234:1234" ]
}

@test "entrypoint infers ids from the work dir owner when no override" {
  # Chown to a fixed, unusual id rather than reading the current owner.
  # The bats container runs as root, so the work dir would otherwise be
  # owned by 0 -- which the 0-guard correctly rejects, making the test pass
  # for the wrong reason and never exercising inference at all.
  chown 4321:4321 "$TMP/work"
  run_ep true
  [ "$status" -eq 0 ]
  [ "$(cat "$GOSU_LOG")" = "4321:4321" ]
}

@test "entrypoint refuses to remap to uid 0" {
  HOST_UID=0 HOST_GID=0 run_ep true
  [ "$status" -eq 0 ]
  [ "$(cat "$GOSU_LOG")" = "1000:1000" ]
}

@test "entrypoint sources the vivado settings script" {
  echo 'export XILINX_VIVADO=/tools/Xilinx/Vivado/2024.1' > "$TMP/settings.sh"
  run_ep bash -c 'echo "V=$XILINX_VIVADO"'
  [[ "$output" == *"V=/tools/Xilinx/Vivado/2024.1"* ]]
}

@test "entrypoint sources the vitis settings when the variant has them" {
  echo 'export XILINX_VITIS=/tools/Xilinx/Vitis/2024.1' > "$TMP/vitis-settings.sh"
  run_ep bash -c 'echo "T=$XILINX_VITIS"'
  [[ "$output" == *"T=/tools/Xilinx/Vitis/2024.1"* ]]
}

@test "entrypoint sources vitis settings on the --user path too" {
  # The two identity branches must not drift: a variant started with
  # --user must get the same environment as one started as root.
  echo 'export XILINX_VITIS=/tools/Xilinx/Vitis/2024.1' > "$TMP/vitis-settings.sh"
  FAKE_EUID=1234 run_ep bash -c 'echo "T=$XILINX_VITIS"'
  [[ "$output" == *"T=/tools/Xilinx/Vitis/2024.1"* ]]
}

@test "entrypoint starts cleanly when the vitis settings are absent" {
  # The default image has no Vitis. A missing optional file must not be an
  # error, or `set -e` turns the whole default image into a boot failure.
  VITIS_SETTINGS="$TMP/does-not-exist.sh" run_ep bash -c 'echo ran'
  [ "$status" -eq 0 ]
  [[ "$output" == *"ran"* ]]
}

@test "entrypoint skips reconciliation when already non-root" {
  FAKE_EUID=1234 run_ep bash -c 'echo ran'
  [ "$status" -eq 0 ]
  [[ "$output" == *"ran"* ]]
  [ ! -f "$GOSU_LOG" ]
}

@test "entrypoint still sets HOME in the non-root branch" {
  FAKE_EUID=1234 HOME=/root run_ep bash -c 'echo "HOME=$HOME"'
  [[ "$output" != *"HOME=/root"* ]]
}

@test "entrypoint passes through the exit code of the command" {
  run_ep bash -c 'exit 7'
  [ "$status" -eq 7 ]
}
