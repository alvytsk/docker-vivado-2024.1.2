#!/usr/bin/env bats

load helpers

setup() {
  TMP="$(mktemp -d)"
  mkdir -p "$TMP/media" "$TMP/mnt" "$TMP/dest/Vivado/2024.1" "$TMP/dest/.xinstall" "$TMP/tmp"
  touch "$TMP/media/base.iso" "$TMP/media/update.iso"
  touch "$TMP/dest/Vivado/2024.1/settings64.sh"
  echo 'Edition=Vivado ML Standard' > "$TMP/config.txt"
  export DRY_RUN=1 LOG="$TMP/dry.log"
}

teardown() { rm -rf "$TMP"; }

# INSTALLER_LIB must point at the repo copy: the default is the in-container
# scaffolding path /mnt/build/installer.sh, which does not exist on the test
# host, and container-install.sh sources it unconditionally at the top -- so
# without this every test here would die before reaching its assertion.
run_ci() {
  MEDIA_DIR="$TMP/media" DEST="$TMP/dest" CONFIG="$TMP/config.txt" \
  MOUNT_DIR="$TMP/mnt" BASE_ISO=base.iso UPDATE_ISO=update.iso \
  DRY_RUN=1 DRY_LOG="$LOG" SCRATCH_DIR="$TMP/tmp" \
  INSTALLER_LIB="$REPO_ROOT/lib/installer.sh" \
  run bash "$REPO_ROOT/scripts/container-install.sh"
}

# What this file can and cannot prove: container-install.sh calls the installer
# through the shared functions, so its dry-run log records `xsetup_install ...`
# and `xsetup_update ...`, never `-b Install` or the EULA flags. ORDER and
# SEQUENCING are testable here; the argv those functions produce is tested in
# test/unit/installer.bats, against a fake xsetup. Asserting `-b Install`
# against this log would only ever assert that the log format has not changed.
@test "container-install runs Install before Update" {
  run_ci
  [ "$status" -eq 0 ]
  local install_line update_line
  install_line="$(grep -n '^xsetup_install ' "$LOG" | head -1 | cut -d: -f1)"
  update_line="$(grep -n '^xsetup_update ' "$LOG" | head -1 | cut -d: -f1)"
  [ -n "$install_line" ] && [ -n "$update_line" ]
  [ "$install_line" -lt "$update_line" ]
}

@test "container-install invokes the installer only through lib/installer.sh" {
  # A future edit that inlines `xsetup -a ... -b Install` here would silently
  # desynchronise the default image from the Vitis variant. Catch it in review
  # by catching it in the test.
  run grep -nE '(^|[^_a-z])xsetup +-' "$REPO_ROOT/scripts/container-install.sh"
  [ "$status" -ne 0 ]
}

@test "container-install runs Install against the BASE iso and Update against the UPDATE iso" {
  run_ci
  local base_mount update_mount install_line update_line
  base_mount="$(grep -n "mount .*base.iso" "$LOG" | head -1 | cut -d: -f1)"
  update_mount="$(grep -n "mount .*update.iso" "$LOG" | head -1 | cut -d: -f1)"
  install_line="$(grep -n '^xsetup_install ' "$LOG" | head -1 | cut -d: -f1)"
  update_line="$(grep -n '^xsetup_update ' "$LOG" | head -1 | cut -d: -f1)"
  [ "$base_mount" -lt "$install_line" ]
  [ "$install_line" -lt "$update_mount" ]
  [ "$update_mount" -lt "$update_line" ]
}

@test "container-install aborts when the loop mount produced nothing" {
  rm -rf "$TMP/mnt"
  MEDIA_DIR="$TMP/media" DEST="$TMP/dest" CONFIG="$TMP/config.txt" \
  MOUNT_DIR="$TMP/does-not-exist" BASE_ISO=base.iso UPDATE_ISO=update.iso \
  DRY_RUN=1 DRY_LOG="$LOG" SCRATCH_DIR="$TMP/tmp" MOUNT_MUST_EXIST=1 \
  INSTALLER_LIB="$REPO_ROOT/lib/installer.sh" \
  run bash "$REPO_ROOT/scripts/container-install.sh"
  [ "$status" -ne 0 ]
}

@test "container-install refuses to Update when the base install is absent" {
  rm -f "$TMP/dest/Vivado/2024.1/settings64.sh"
  run_ci
  [ "$status" -ne 0 ]
  [[ "$output" == *"settings64.sh"* ]]
}

@test "container-install pins HOME so xsetup state lands where Task 2 recorded" {
  # Asserted through the script text as well as behaviour: HOME must be
  # exported before the first xsetup call, and a later refactor that moves it
  # below the installer invocations reintroduces the bug invisibly.
  run grep -n 'export HOME=' "$REPO_ROOT/scripts/container-install.sh"
  [ "$status" -eq 0 ]
  local home_line install_line
  home_line="$(grep -n 'export HOME=' "$REPO_ROOT/scripts/container-install.sh" | head -1 | cut -d: -f1)"
  install_line="$(grep -n 'run_step xsetup_install' "$REPO_ROOT/scripts/container-install.sh" | head -1 | cut -d: -f1)"
  [ "$home_line" -lt "$install_line" ]
}

@test "container-install directs installer scratch at SCRATCH_DIR before installing" {
  run grep -n 'export TMPDIR=' "$REPO_ROOT/scripts/container-install.sh"
  [ "$status" -eq 0 ]
  local tmp_line install_line
  tmp_line="$(grep -n 'export TMPDIR=' "$REPO_ROOT/scripts/container-install.sh" | head -1 | cut -d: -f1)"
  install_line="$(grep -n 'run_step xsetup_install' "$REPO_ROOT/scripts/container-install.sh" | head -1 | cut -d: -f1)"
  [ "$tmp_line" -lt "$install_line" ]
}

@test "container-install prunes every recorded scratch path, not just one" {
  # run_ci overrides SCRATCH_DIR, so assert against THAT value -- matching the
  # production default /tmp/xinstall here would be a test that can never pass.
  run_ci
  [ "$status" -eq 0 ]
  local line
  line="$(grep '^prune ' "$LOG" | head -1)"
  [ -n "$line" ]
  [[ "$line" == *"$TMP/tmp"* ]]                 # SCRATCH_DIR, as overridden
  # Both halves of SCRATCH_EXTRA, as Task 2 actually observed them. Pruning
  # only /root/.Xilinx/xinstall would leave registry/ behind in the image.
  [[ "$line" == *"/root/.Xilinx"* ]]
  [[ "$line" == *"/tmp/hsperfdata_root"* ]]
}

@test "container-install refuses a scratch path that escapes DEST via .." {
  # The lexical-prefix trap: this string is inside DEST but does not start
  # with it, and a raw prefix check would let it through to `rm -rf`.
  MEDIA_DIR="$TMP/media" DEST="$TMP/dest" CONFIG="$TMP/config.txt" \
  MOUNT_DIR="$TMP/mnt" BASE_ISO=base.iso UPDATE_ISO=update.iso \
  DRY_RUN=1 DRY_LOG="$LOG" SCRATCH_DIR="$TMP/tmp" \
  SCRATCH_EXTRA="$TMP/dest/sub/../.xinstall" \
  SCRATCH_ALLOW="$TMP" \
  INSTALLER_LIB="$REPO_ROOT/lib/installer.sh" \
  run bash "$REPO_ROOT/scripts/container-install.sh"
  [ "$status" -ne 0 ]
  [ -d "$TMP/dest/.xinstall" ]
}

@test "container-install refuses a scratch path outside the approved roots" {
  MEDIA_DIR="$TMP/media" DEST="$TMP/dest" CONFIG="$TMP/config.txt" \
  MOUNT_DIR="$TMP/mnt" BASE_ISO=base.iso UPDATE_ISO=update.iso \
  DRY_RUN=1 DRY_LOG="$LOG" SCRATCH_DIR="$TMP/tmp" \
  SCRATCH_EXTRA="/usr/lib" \
  INSTALLER_LIB="$REPO_ROOT/lib/installer.sh" \
  run bash "$REPO_ROOT/scripts/container-install.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"approved roots"* ]]
  [ -d /usr/lib ]
}

@test "container-install refuses a scratch path inside DEST, before installing" {
  # A mis-set SCRATCH_EXTRA must be rejected at startup, not discovered when
  # the final cleanup deletes the install it just spent four hours producing.
  MEDIA_DIR="$TMP/media" DEST="$TMP/dest" CONFIG="$TMP/config.txt" \
  MOUNT_DIR="$TMP/mnt" BASE_ISO=base.iso UPDATE_ISO=update.iso \
  DRY_RUN=1 DRY_LOG="$LOG" SCRATCH_DIR="$TMP/tmp" \
  SCRATCH_EXTRA="$TMP/dest/.xinstall" \
  INSTALLER_LIB="$REPO_ROOT/lib/installer.sh" \
  run bash "$REPO_ROOT/scripts/container-install.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *".xinstall"* ]]
  [ -d "$TMP/dest/.xinstall" ]
  # and it must have failed before doing anything at all: either no log was
  # written, or nothing in it names an installer step.
  run grep -q 'xsetup_install' "$LOG"
  [ "$status" -ne 0 ]
}

@test "container-install preserves .xinstall through cleanup" {
  run_ci
  [ -d "$TMP/dest/.xinstall" ]
}

@test "container-install never deletes .xinstall even by pattern" {
  run_ci
  run grep -E 'rm .*\.xinstall' "$LOG"
  [ "$status" -ne 0 ]
}

@test "container-install copies installer logs before pruning" {
  run_ci
  local copy_line prune_line
  copy_line="$(grep -n 'copy-logs' "$LOG" | head -1 | cut -d: -f1)"
  prune_line="$(grep -n 'prune' "$LOG" | head -1 | cut -d: -f1)"
  [ "$copy_line" -lt "$prune_line" ]
}

@test "container-install collects logs when a step FAILS, not only on success" {
  # REAL_LOGS=1 makes copy_logs actually copy despite DRY_RUN. Without it the
  # copy short-circuits, the test asserts nothing about log collection, and a
  # broken trap passes. The rest stays dry so no ISO is mounted.
  mkdir -p "$TMP/logsrc" && echo x > "$TMP/logsrc/install.log"
  MEDIA_DIR="$TMP/media" DEST="$TMP/dest" CONFIG="$TMP/config.txt" \
  MOUNT_DIR="$TMP/mnt" BASE_ISO=base.iso UPDATE_ISO=update.iso \
  DRY_RUN=1 DRY_LOG="$LOG" SCRATCH_DIR="$TMP/tmp" \
  LOG_SRC="$TMP/logsrc" LOG_DEST="$TMP/logdest" REAL_LOGS=1 \
  INSTALLER_LIB="$REPO_ROOT/lib/installer.sh" \
  FORCE_FAIL_AFTER_INSTALL=1 \
  run bash "$REPO_ROOT/scripts/container-install.sh"
  [ "$status" -ne 0 ]
  # copy_logs must have been reachable at trap time -- a definition ordering
  # bug shows up here as "command not found" and an empty logdest.
  [[ "$output" != *"command not found"* ]]
  # The file must have actually arrived. This is the assertion that makes the
  # test about log collection rather than about exit codes.
  [ -f "$TMP/logdest/install.log" ]
}

@test "container-install collects logs from EVERY candidate directory" {
  # LOG_SRC is a space-separated list; a quoting bug that treats it as one
  # path silently collects nothing from the second directory onwards.
  mkdir -p "$TMP/lsa" "$TMP/lsb"
  echo a > "$TMP/lsa/first.log"
  echo b > "$TMP/lsb/second.log"
  MEDIA_DIR="$TMP/media" DEST="$TMP/dest" CONFIG="$TMP/config.txt" \
  MOUNT_DIR="$TMP/mnt" BASE_ISO=base.iso UPDATE_ISO=update.iso \
  DRY_RUN=1 DRY_LOG="$LOG" SCRATCH_DIR="$TMP/tmp" \
  LOG_SRC="$TMP/lsa $TMP/lsb" LOG_DEST="$TMP/logdest2" REAL_LOGS=1 \
  INSTALLER_LIB="$REPO_ROOT/lib/installer.sh" \
  run bash "$REPO_ROOT/scripts/container-install.sh"
  [ "$status" -eq 0 ]
  [ -f "$TMP/logdest2/first.log" ]
  [ -f "$TMP/logdest2/second.log" ]
}

@test "the build context is allow-listed" {
  # A deny-list drifts: the day someone adds a directory, it silently joins
  # the context. Assert the allow-list shape instead.
  run grep -qx '\*' "$REPO_ROOT/.dockerignore"
  [ "$status" -eq 0 ]
  run grep -qx '!lib' "$REPO_ROOT/.dockerignore"
  [ "$status" -eq 0 ]
  run grep -qx '!scripts' "$REPO_ROOT/.dockerignore"
  [ "$status" -eq 0 ]
}

@test "container-install never touches the Crack directory" {
  run grep -ri 'crack\|\.lic' "$REPO_ROOT/scripts/container-install.sh"
  [ "$status" -ne 0 ]
}
