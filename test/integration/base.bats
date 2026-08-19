#!/usr/bin/env bats

IMAGE="${BASE_IMAGE:-vivado-base:22.04}"

in_image() { docker run --rm --network=none "$IMAGE" "$@"; }

@test "base: gosu is installed and executable" {
  run in_image gosu --version
  [ "$status" -eq 0 ]
}

@test "base: vivado account exists at 1000" {
  run in_image id -u vivado
  [ "$output" = "1000" ]
}

@test "base: /work exists and is owned by 1000:1000" {
  run in_image stat -c '%u:%g' /work
  [ "$output" = "1000:1000" ]
}

@test "base: /home/vivado is world-writable" {
  run in_image stat -c '%a' /home/vivado
  [ "$output" = "777" ]
}

@test "base: apt lists were removed in the same layer that installed them" {
  run in_image bash -c 'ls -A /var/lib/apt/lists | wc -l'
  [ "$output" = "0" ]
}

@test "base: X libraries required by headless vivado are present" {
  for lib in libX11.so.6 libXext.so.6 libXrender.so.1 libXtst.so.6 libXi.so.6; do
    run in_image bash -c "ldconfig -p | grep -q $lib"
    [ "$status" -eq 0 ]
  done
}

@test "base: image is built from the pinned digest" {
  run bash -c "docker image inspect $IMAGE -f '{{json .Config.Labels}}' | grep -q 2edbbc5d"
  [ "$status" -eq 0 ]
}

@test "base: en_US.UTF-8 is GENERATED, not merely installable" {
  # Vivado's launcher unconditionally exports LC_ALL=en_US.UTF-8. If that
  # locale does not exist, vivado aborts with an unhandled std::runtime_error
  # that never mentions locales. Having the `locales` package is not enough --
  # the locale must actually be generated.
  run docker run --rm --network=none "$IMAGE" locale -a
  [ "$status" -eq 0 ]
  [[ "$output" == *"en_US.utf8"* ]]
}

@test "base: a forced en_US.UTF-8 locale does not fail" {
  # The exact thing rdiArgs.sh does, reproduced without needing Vivado.
  run docker run --rm --network=none -e LC_ALL=en_US.UTF-8 -e LANG=en_US.UTF-8 \
    "$IMAGE" bash -c 'locale >/dev/null 2>/tmp/e; cat /tmp/e'
  [ "$status" -eq 0 ]
  [[ "$output" != *"cannot change locale"* ]]
}
