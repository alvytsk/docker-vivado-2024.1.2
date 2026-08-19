#!/usr/bin/env bash
set -euo pipefail

# Criterion 5 requires the COMPLETE smoke flow under both identity modes, not
# just a `touch`. Vivado writes caches, journals and project state through
# $HOME and $WORK; a bare touch would never surface a HOME or permission
# fault that only appears once the tool actually runs.

IMAGE="${FINAL_IMAGE:-vivado:2024.1.2}"
PART="${SMOKE_PART:-xc7z020clg484-1}"
TCL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Vivado creates /work/smoke_out and a whole project tree owned by whatever
# uid it ran as, with ordinary 0755 directories. When that uid is 1234 and the
# invoking user is 1000, `rm -rf "$work"` fails with EACCES on every directory
# it needs to unlink from -- so the run "passes" and then the script dies on
# cleanup, or leaves gigabytes behind. Delete through a root container: the
# same daemon that created the files, and no sudo on the host.
cleanup_work() {
  local work="$1"
  docker run --rm --network=none -v "${work}:/work" --user 0:0 \
    --entrypoint /bin/bash "$IMAGE" -c 'find /work -mindepth 1 -delete' \
    >/dev/null 2>&1 || true
  # Only the (empty, host-owned) mktemp dir is left for the host to remove.
  rmdir "$work" 2>/dev/null || true
}

# On failure the tree is deliberately kept for inspection -- but say so, and
# say how to remove it, because the user cannot simply rm it either.
keep_work() {
  local mode="$1" work="$2"
  echo "  [$mode] work dir kept for inspection: $work" >&2
  echo "  remove with: docker run --rm -v $work:/work --user 0:0 \\" >&2
  echo "               --entrypoint /bin/bash $IMAGE -c 'find /work -mindepth 1 -delete'" >&2
}

# run_mode <mode> <uid> <gid> [expect_uid] [expect_gid]
#
# The requested identity and the expected artifact owner are separate on
# purpose: HOST_UID=0 is documented to resolve to 1000, so "asked for 0, expect
# 1000" is a real case that must be assertable rather than skipped.
run_mode() {
  local mode="$1" uid="$2" gid="$3"
  local exp_uid="${4:-$uid}" exp_gid="${5:-$gid}"
  local work; work="$(mktemp -d)"
  chmod 0777 "$work"
  cp "$TCL_DIR/zynq_smoke.tcl" "$work/"

  local -a idargs=()
  case "$mode" in
    hostenv) idargs=(-e "HOST_UID=${uid}" -e "HOST_GID=${gid}") ;;
    user)    idargs=(--user "${uid}:${gid}") ;;
    *) echo "unknown mode $mode" >&2; return 1 ;;
  esac

  echo "=== smoke [$mode] requested ${uid}:${gid}, expecting artifacts owned by ${exp_uid}:${exp_gid} ==="
  # --init: the entrypoint execs, so Vivado becomes PID 1, and it does not
  # reap the children launch_runs forks. Without an init these accumulate as
  # zombies for the length of a synthesis run.
  docker run --rm --init --network=none "${idargs[@]}" \
    -e "SMOKE_PART=${PART}" -v "${work}:/work" \
    "$IMAGE" vivado -mode batch -nojournal -nolog -source /work/zynq_smoke.tcl \
    2>&1 | tee "$work/smoke.out"

  grep -q SMOKE_OK "$work/smoke.out" || {
    echo "FAIL[$mode]: no SMOKE_OK" >&2; keep_work "$mode" "$work"; return 1; }

  local f owner
  for f in smoke.bit smoke.xsa; do
    [[ -s "$work/$f" ]] || {
      echo "FAIL[$mode]: $f missing or empty" >&2; keep_work "$mode" "$work"; return 1; }
    owner="$(stat -c%u "$work/$f")"
    [[ "$owner" == "$exp_uid" ]] || {
      echo "FAIL[$mode]: $f owned by $owner, expected $exp_uid" >&2
      keep_work "$mode" "$work"; return 1; }
  done

  if grep -qiE 'licen[sc]e.*(not|fail|error|expired)|no license' "$work/smoke.out"; then
    echo "FAIL[$mode]: licensing error in a license-free flow" >&2
    keep_work "$mode" "$work"
    return 1
  fi

  cleanup_work "$work"
  echo "ok [$mode]"
}

# Both modes required by criterion 5, at a NON-1000 uid so the assertion
# cannot pass vacuously on a machine whose user happens to be 1000.
run_mode hostenv 1234 1234
run_mode user    1234 1234

# Plus the ordinary developer path, as the invoking user -- except when that
# user is root. HOST_UID=0 is deliberately treated as "no hint" by
# ir_resolve_id, so the entrypoint falls back to 1000 and the artifacts come
# out owned by 1000. Asserting ownership 0 would fail on exactly the behaviour
# the design calls for, which is a broken test rather than a broken image, and
# it would fail only in root-run CI.
me_uid="$(id -u)"; me_gid="$(id -g)"
if [[ "$me_uid" == "0" ]]; then
  echo "=== invoking user is root: asserting the documented 0 -> 1000 fallback ==="
  run_mode hostenv 0 0 1000 1000
else
  run_mode hostenv "$me_uid" "$me_gid"
fi

echo "smoke: OK -- bit and xsa produced in all identity modes, no license error"
