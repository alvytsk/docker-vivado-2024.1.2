#!/usr/bin/env bats

IMAGE="${VITIS_IMAGE:-vivado-vitis:2024.1.2}"

@test "vitis: xsct answers headlessly at the exact patch version" {
  run docker run --rm --network=none "$IMAGE" xsct -eval 'puts [version]'
  [ "$status" -eq 0 ]
  # Must be the EXACT patch level. Matching bare "2024.1" would let an
  # un-updated Vitis pass, which is the whole failure this guards.
  [[ "$output" == *"2024.1.2"* ]]
}

@test "vitis: vivado is still 2024.1.2 in the combined image" {
  run docker run --rm --network=none "$IMAGE" vivado -version
  [ "$status" -eq 0 ]
  [[ "$output" == *"2024.1.2"* ]]
}

@test "vitis: the entrypoint sourced the Vitis settings, not merely shipped them" {
  # xsct answering is necessary but not sufficient -- assert the environment
  # AMD's setup instructions define, because that is what a user's own
  # scripts will reach for.
  run docker run --rm --network=none "$IMAGE" bash -c 'echo "T=$XILINX_VITIS"'
  [[ "$output" == *"/tools/Xilinx/Vitis/2024.1"* ]]
  run docker run --rm --network=none "$IMAGE" bash -c 'command -v xsct'
  [ "$status" -eq 0 ]
}

@test "vitis: the variant carries the same runtime contract as the default" {
  run docker run --rm --network=none "$IMAGE" bash -c 'echo "$XILINX_VIVADO"'
  [[ "$output" == *"/tools/Xilinx/Vivado/2024.1"* ]]
  run docker run --rm --network=none "$IMAGE" id -u
  [ "$output" != "0" ]
  run docker run --rm --network=none "$IMAGE" pwd
  [ "$output" = "/work" ]
}
