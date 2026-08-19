#!/usr/bin/env bats

IMAGE="${FINAL_IMAGE:-vivado:2024.1.2}"

setup() {
  # MUST live under TEST_SCRATCH: bind sources resolve on the daemon host,
  # so a path that exists only inside this container would mount the wrong
  # directory (or fail outright).
  : "${TEST_SCRATCH:?TEST_SCRATCH must be set and host-visible}"
  WORK="$(mktemp -d "$TEST_SCRATCH/identity.XXXXXX")"
  chmod 0777 "$WORK"
}
teardown() { rm -rf "$WORK"; }

@test "identity case 1: HOST_UID override writes files owned by 1234" {
  docker run --rm --network=none -e HOST_UID=1234 -e HOST_GID=1234 \
    -v "$WORK:/work" "$IMAGE" bash -c 'touch /work/a'
  run stat -c%u "$WORK/a"
  [ "$output" = "1234" ]
}

@test "identity case 2: explicit --user writes files owned by 1234" {
  docker run --rm --network=none --user 1234:1234 \
    -v "$WORK:/work" "$IMAGE" bash -c 'touch /work/b'
  run stat -c%u "$WORK/b"
  [ "$output" = "1234" ]
}

@test "identity case 3: ids are inferred from the /work owner with no override" {
  # No HOST_UID, no --user. Only the bind-mount owner can supply the id,
  # so an entrypoint that never inspects /work fails here and nowhere else.
  chown 1234:1234 "$WORK"
  docker run --rm --network=none -v "$WORK:/work" "$IMAGE" bash -c 'touch /work/c'
  run stat -c%u "$WORK/c"
  [ "$output" = "1234" ]
}

@test "identity: HOME is set, writable, and never /root (criterion 8)" {
  run docker run --rm --network=none "$IMAGE" \
    bash -c 'echo "UID=$(id -u) HOME=$HOME"; test -w "$HOME" && echo WRITABLE'
  [ "$status" -eq 0 ]
  [[ "$output" != *"UID=0"* ]]
  [[ "$output" != *"HOME=/root"* ]]
  [[ "$output" == *"WRITABLE"* ]]
}

@test "identity: no bind mount does not remap the user to root" {
  run docker run --rm --network=none "$IMAGE" id -u
  [ "$output" != "0" ]
}

@test "identity: a root-owned /work does not remap the user to root" {
  chown 0:0 "$WORK"
  run docker run --rm --network=none -v "$WORK:/work" "$IMAGE" id -u
  [ "$output" != "0" ]
}
