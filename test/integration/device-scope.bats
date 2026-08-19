#!/usr/bin/env bats

IMAGE="${FINAL_IMAGE:-vivado:2024.1.2}"

setup() {
  : "${TEST_SCRATCH:?TEST_SCRATCH must be set and host-visible}"
  WORK="$(mktemp -d "$TEST_SCRATCH/devscope.XXXXXX")"; chmod 0777 "$WORK"
  cp "$BATS_TEST_DIRNAME/../zynq_smoke.tcl" "$BATS_TEST_DIRNAME/../parts_probe.tcl" \
     "$BATS_TEST_DIRNAME/../parts_list.tcl" "$WORK/"
}

# Vivado runs as the invoking uid here (the harness is root, so uid 0) and
# leaves a project tree behind. Removing it through a root container matches
# run-smoke.sh and works regardless of which uid produced it.
teardown() {
  docker run --rm --network=none -v "$WORK:/work" --user 0:0 \
    --entrypoint /bin/bash "$IMAGE" -c 'find /work -mindepth 1 -delete' \
    >/dev/null 2>&1 || true
  rm -rf "$WORK"
}

@test "device scope: an in-subset part (7z020) synthesises" {
  run docker run --rm --network=none -e SMOKE_PART=xc7z020clg484-1 \
    -v "$WORK:/work" "$IMAGE" \
    vivado -mode batch -nojournal -nolog -source /work/zynq_smoke.tcl
  [ "$status" -eq 0 ]
  [[ "$output" == *"SMOKE_OK"* ]]
}

@test "device scope: an out-of-subset part (7z045) is absent, not merely unlicensed" {
  # The plan assumed 7z045 device data would be installed and that using it
  # would fail with a LICENSING diagnostic. The real image disproves that:
  # under Vivado ML Standard the installer ships only the license-free Zynq
  # devices, so xc7z045 is not present at all and get_parts returns nothing.
  # The boundary is enforced by DEVICE DATA SCOPE, which is stronger than a
  # licence check -- there is nothing to license, and nothing to circumvent.
  run docker run --rm --network=none -e PROBE_PART=xc7z045ffg900-2 \
    -v "$WORK:/work" "$IMAGE" \
    vivado -mode batch -nojournal -nolog -source /work/parts_probe.tcl
  [ "$status" -eq 0 ]
  [[ "$output" == *"PARTS=0"* ]]
}

@test "device scope: building for 7z045 fails rather than silently succeeding" {
  # Whatever the mechanism, the criterion is that an out-of-subset part cannot
  # produce a bitstream. Assert the outcome, not the diagnostic wording.
  run docker run --rm --network=none -e SMOKE_PART=xc7z045ffg900-2 \
    -v "$WORK:/work" "$IMAGE" \
    vivado -mode batch -nojournal -nolog -source /work/zynq_smoke.tcl
  [ "$status" -ne 0 ]
  [[ "$output" != *"SMOKE_OK"* ]]
}

@test "device scope: exactly the seven license-free Zynq-7000 devices are installed" {
  # Criterion 7, asserted positively. Locks the shipped device set to the
  # subset the spec promises, so a future config change that silently widens
  # or narrows it is caught here rather than by a user.
  run docker run --rm --network=none -v "$WORK:/work" "$IMAGE" \
    vivado -mode batch -nojournal -nolog -source /work/parts_list.tcl
  [ "$status" -eq 0 ]
  for d in xc7z007s xc7z010 xc7z012s xc7z014s xc7z015 xc7z020 xc7z030; do
    [[ "$output" == *"$d"* ]] || { echo "missing in-subset device: $d" >&2; return 1; }
  done
  for d in xc7z035 xc7z045 xc7z100; do
    [[ "$output" != *"$d"* ]] || { echo "out-of-subset device present: $d" >&2; return 1; }
  done
}
