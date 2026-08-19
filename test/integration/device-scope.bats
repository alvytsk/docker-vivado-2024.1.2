#!/usr/bin/env bats

IMAGE="${FINAL_IMAGE:-vivado:2024.1.2}"

setup() {
  : "${TEST_SCRATCH:?TEST_SCRATCH must be set and host-visible}"
  WORK="$(mktemp -d "$TEST_SCRATCH/devscope.XXXXXX")"; chmod 0777 "$WORK"
  cp "$BATS_TEST_DIRNAME/../zynq_smoke.tcl" "$BATS_TEST_DIRNAME/../parts_probe.tcl" "$WORK/"
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

@test "device scope: the 7z045 part DATA is installed (so failure is licensing)" {
  # Establish this first. Without it, the next test would pass just as
  # happily on a missing part or a typo'd part string -- proving nothing
  # about licensing, which is what the criterion is actually about.
  run docker run --rm --network=none -e PROBE_PART=xc7z045ffg900-2 \
    -v "$WORK:/work" "$IMAGE" \
    vivado -mode batch -nojournal -nolog -source /work/parts_probe.tcl
  [ "$status" -eq 0 ]
  [[ "$output" == *"PARTS=1"* ]]
}

@test "device scope: 7z045 fails with a LICENSING diagnostic specifically" {
  run docker run --rm --network=none -e SMOKE_PART=xc7z045ffg900-2 \
    -v "$WORK:/work" "$IMAGE" \
    vivado -mode batch -nojournal -nolog -source /work/zynq_smoke.tcl
  [ "$status" -ne 0 ]
  # Case-insensitive, and licence-specific. "No such part" or "unsupported"
  # would indicate missing device data, which the previous test rules out
  # and which would be a different bug entirely.
  [[ "$(echo "$output" | tr 'A-Z' 'a-z')" =~ licen ]]
}
