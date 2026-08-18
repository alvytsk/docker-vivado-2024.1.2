#!/usr/bin/env bash
set -euo pipefail

MEDIA_DIR="${MEDIA_DIR:-/media}"
DEST="${DEST:-/tools/Xilinx}"
CONFIG="${CONFIG:-/mnt/build/install_config.txt}"
MOUNT_DIR="${MOUNT_DIR:-/mnt/iso}"
# Scratch, from "Installer scratch location" in docs/installer-facts.md.
#
# Task 2 established that xsetup IGNORES TMPDIR: a ConfigGen run with
# TMPDIR=/probe-tmp left that directory empty and went on writing to
# /root/.Xilinx and /tmp regardless. SCRATCH_DIR is therefore vestigial -- the
# TMPDIR export below costs nothing and would start working if a future
# installer honoured it -- and SCRATCH_EXTRA does all of the real work.
#
# The observed scratch is the WHOLE of /root/.Xilinx (both registry/ and
# xinstall/), not just xinstall/, plus /tmp/hsperfdata_root from the bundled
# JVM. Pruning only xinstall/ would leave registry/ in the committed image and
# look like it had worked. Nothing here is needed at runtime: the final image
# sets XILINX_LOCAL_USER_DATA=no and never runs as root, and the install record
# that -b Add and -b Update depend on lives at $DEST/.xinstall, which the
# validation below refuses to touch.
SCRATCH_DIR="${SCRATCH_DIR:-/tmp/xinstall}"
SCRATCH_EXTRA="${SCRATCH_EXTRA:-/root/.Xilinx /tmp/hsperfdata_root}"
BASE_ISO="${BASE_ISO:-Xilinx_Unified_2024_1_0522_2023.iso}"
UPDATE_ISO="${UPDATE_ISO:-Xilinx_Vivado_Vitis_Update_2024_1_2_0906_0624.iso}"
LOG_DEST="${LOG_DEST:-/var/log/xinstall}"
# Candidate log directories, from docs/installer-facts.md. It arrives as a
# space-separated STRING because it has to be settable through `docker run -e`,
# and is split ONCE into an array here. Iterating over the bare scalar would be
# SC2086 and `make lint` must pass with no warnings.
LOG_SRC="${LOG_SRC:-/root/.Xilinx/xinstall /tmp}"
IFS=' ' read -r -a LOG_DIRS <<< "$LOG_SRC"
IFS=' ' read -r -a SCRATCH_DIRS <<< "${SCRATCH_DIR} ${SCRATCH_EXTRA}"
# Roots under which a prune target is permitted to live. Anything else is
# refused outright: a prefix check alone only rules out the paths someone
# thought to forbid, whereas an allow-list rules out everything nobody thought
# about. Override only with a path you are willing to see `rm -rf`'d.
SCRATCH_ALLOW="${SCRATCH_ALLOW:-/tmp /root/.Xilinx}"

# Lexical path normalisation, in pure bash. `realpath -m` would be the obvious
# tool and is not usable here: busybox's realpath (the bats image) has no -m,
# and the paths need not exist yet. Nothing here touches the filesystem, which
# is the point -- the decision must not depend on what happens to exist.
norm_path() {
  local p="$1" out="" part
  [[ "$p" == /* ]] || p="${PWD}/${p}"
  local IFS=/
  for part in $p; do
    case "$part" in
      ''|.) continue ;;
      ..)   out="${out%/*}" ;;
      *)    out="${out}/${part}" ;;
    esac
  done
  printf '%s\n' "${out:-/}"
}

# Validate the prune targets NOW rather than after a four-hour install: a
# SCRATCH_EXTRA that points inside $DEST would delete the thing we just built,
# and it would do so at the very last step, with no way back but a rebuild.
#
# Both checks are lexical AND normalised. Comparing raw strings is not enough:
# `/tools/Xilinx/../Xilinx` does not start with any forbidden prefix, is not on
# any allow-list, and deletes the entire installation.
DEST_N="$(norm_path "$DEST")"
IFS=' ' read -r -a SCRATCH_ALLOW_DIRS <<< "$SCRATCH_ALLOW"
for _i in "${!SCRATCH_DIRS[@]}"; do
  _d="$(norm_path "${SCRATCH_DIRS[$_i]}")"
  SCRATCH_DIRS[_i]="$_d"   # prune the normalised form, not the input
  case "$_d" in
    ""|"/"|"$DEST_N"|"$DEST_N"/*)
      echo "ERROR: refusing a scratch path at / or inside \$DEST: '${_d}'" >&2
      exit 1 ;;
  esac
  _ok=0
  for _a in "${SCRATCH_ALLOW_DIRS[@]}"; do
    _a="$(norm_path "$_a")"
    if [[ "$_d" == "$_a" || "$_d" == "$_a"/* ]]; then _ok=1; break; fi
  done
  if [[ "$_ok" != "1" ]]; then
    echo "ERROR: scratch path '${_d}' is outside the approved roots (${SCRATCH_ALLOW})" >&2
    exit 1
  fi
done
unset _i _d _a _ok
DRY_RUN="${DRY_RUN:-0}"
# Dry runs skip the copy so unit tests do not write to /var/log; the test that
# is specifically about log collection sets REAL_LOGS=1 with its own LOG_DEST.
REAL_LOGS="${REAL_LOGS:-0}"
DRY_LOG="${DRY_LOG:-/dev/stdout}"
MOUNT_MUST_EXIST="${MOUNT_MUST_EXIST:-0}"

# HOME is not merely cosmetic here. xsetup writes .Xilinx/ under $HOME: the
# install record that `-b Add` and `-b Update` read, and the logs Task 2
# located. `docker run` does not guarantee HOME is set to anything useful for
# a non-login exec, and every discovery command in Task 2 set it explicitly --
# so the paths recorded there are only correct if this one matches. Getting it
# wrong scatters state somewhere the log collection and the Vitis variant will
# not look, and nothing fails until Task 15 does.
INSTALL_HOME="${INSTALL_HOME:-/root}"
export HOME="$INSTALL_HOME"

INSTALLER_LIB="${INSTALLER_LIB:-/mnt/build/installer.sh}"
# shellcheck source=/dev/null
source "$INSTALLER_LIB"

SETTINGS="${DEST}/Vivado/2024.1/settings64.sh"

log() { printf '%s\n' "$*" | tee -a "$DRY_LOG" >/dev/null; }

# ---- functions FIRST -------------------------------------------------
# These must be defined before the trap is installed. Bash executes
# definitions in order, so a trap referencing a function defined further
# down fires as "command not found" on any early failure -- silently, if
# the call is guarded by `|| true`. That is exactly the failure this trap
# exists to prevent.

copy_logs() {
  log "copy-logs ${LOG_DIRS[*]} -> ${LOG_DEST}"
  if [[ "$DRY_RUN" == "1" && "$REAL_LOGS" != "1" ]]; then return 0; fi
  mkdir -p "$LOG_DEST"
  local d
  for d in "${LOG_DIRS[@]}"; do
    [[ -d "$d" ]] || continue
    find "$d" -maxdepth 2 -name '*.log' -exec cp -f {} "$LOG_DEST/" \; 2>/dev/null || true
  done
  return 0
}

prune_scratch() {
  log "prune ${SCRATCH_DIRS[*]}"
  [[ "$DRY_RUN" == "1" ]] && return 0
  # .xinstall is the installer's record of what it installed. Both xsetup_add
  # and xsetup_update read it. It looks like scratch and is not: deleting
  # it yields a working Vivado in which the Vitis variant and all future
  # updates silently cannot run. It lives under $DEST, never under
  # $SCRATCH_DIR, and nothing here may touch $DEST.
  # Targets were validated at startup, before anything was installed.
  local d
  for d in "${SCRATCH_DIRS[@]}"; do
    rm -rf "$d"
  done
  return 0
}

# Logs must be collected on FAILURE, which is when they matter.
on_exit() {
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "container-install: FAILED (rc=$rc); collecting logs" >&2
    copy_logs || true
  fi
  return $rc
}
trap on_exit EXIT

run_step() {
  if [[ "$DRY_RUN" == "1" ]]; then
    log "$*"
  else
    log "$*"
    "$@"
  fi
}

mount_iso() {
  local iso="$1"
  if [[ "$DRY_RUN" == "1" ]]; then
    log "mount -o loop,ro ${MEDIA_DIR}/${iso} ${MOUNT_DIR}"
  else
    mkdir -p "$MOUNT_DIR"
    mount -o loop,ro "${MEDIA_DIR}/${iso}" "$MOUNT_DIR"
  fi
  # An empty mount point means the loop mount silently failed; running
  # xsetup against it would fail confusingly hours later.
  if [[ "$MOUNT_MUST_EXIST" == "1" || "$DRY_RUN" != "1" ]]; then
    if [[ ! -d "$MOUNT_DIR" ]]; then
      echo "ERROR: mount point ${MOUNT_DIR} does not exist" >&2
      return 1
    fi
  fi
}

umount_iso() {
  if [[ "$DRY_RUN" == "1" ]]; then
    log "umount ${MOUNT_DIR}"
  else
    umount "$MOUNT_DIR"
  fi
}

# ---- 0. direct the installer's scratch somewhere we will actually delete --
# If Task 2 recorded that xsetup ignores TMPDIR, this is harmless and
# SCRATCH_EXTRA is doing the real work. If it honours it, this is what makes
# prune_scratch reclaim anything at all.
if [[ "$DRY_RUN" != "1" ]]; then
  mkdir -p "$SCRATCH_DIR"
fi
export TMPDIR="$SCRATCH_DIR"

# ---- 1. base install -------------------------------------------------
mount_iso "$BASE_ISO"
run_step xsetup_install "${MOUNT_DIR}/xsetup" "$CONFIG"
umount_iso

# Test hook: proves the EXIT trap collects logs on an early failure.
[[ "${FORCE_FAIL_AFTER_INSTALL:-0}" == "1" ]] && exit 42

if [[ "$DRY_RUN" != "1" && ! -f "$SETTINGS" ]]; then
  echo "ERROR: base install did not produce ${SETTINGS}" >&2
  exit 1
fi
if [[ "$DRY_RUN" == "1" && ! -f "$SETTINGS" ]]; then
  echo "ERROR: base install did not produce ${SETTINGS}" >&2
  exit 1
fi

# ---- 2. 2024.1.2 update ----------------------------------------------
mount_iso "$UPDATE_ISO"
run_step xsetup_update "${MOUNT_DIR}/xsetup" "$CONFIG"
umount_iso

# ---- 3. copy logs, THEN prune (both defined at the top) --------------
copy_logs
prune_scratch

log "container-install: complete"
