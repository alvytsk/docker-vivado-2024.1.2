#!/usr/bin/env bats

IMAGE="${FINAL_IMAGE:-vivado:2024.1.2}"

@test "final: XILINX_VIVADO resolves without the caller sourcing anything" {
  run docker run --rm --network=none "$IMAGE" bash -c 'echo "$XILINX_VIVADO"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"/tools/Xilinx/Vivado/2024.1"* ]]
}

@test "final: vivado reports 2024.1.2" {
  run docker run --rm --network=none "$IMAGE" vivado -version
  [ "$status" -eq 0 ]
  [[ "$output" == *"2024.1.2"* ]]
}

@test "final: image contains no license file" {
  run docker run --rm --network=none "$IMAGE" \
    bash -c 'find / -name "*.lic" -not -path "*/proc/*" 2>/dev/null | wc -l'
  [ "$output" = "0" ]
}

@test "final: no installer scratch survived into the image" {
  # Task 8's prune is only meaningful if something checks it actually removed
  # the paths the installer used. Without this, a prune aimed at a directory
  # xsetup never wrote is indistinguishable from a working one -- except in
  # the image size, which nobody reads.
  run docker run --rm --network=none "$IMAGE" bash -c \
    'ls -d /tmp/xinstall /root/.Xilinx/xinstall 2>/dev/null | wc -l'
  [ "$output" = "0" ]
}

@test "final: image size is within the recorded ceiling" {
  # The blunt backstop for scratch that escaped the prune under a name nobody
  # anticipated. MAX_IMAGE_GB is recorded from the first good build in Task 11
  # Step 5 with headroom; if a legitimate change grows the image, raise it
  # deliberately and say why in the commit.
  local max="${MAX_IMAGE_GB:-70}"
  run docker image inspect -f '{{.Size}}' "$IMAGE"
  [ "$status" -eq 0 ]
  local gb=$(( output / 1000000000 ))
  echo "image size: ${gb}G (ceiling ${max}G)"
  [ "$gb" -le "$max" ]
}

@test "final: .xinstall is retained for future Add and Update" {
  run docker run --rm --network=none "$IMAGE" ls -d /tools/Xilinx/.xinstall
  [ "$status" -eq 0 ]
}

@test "final: workdir is /work" {
  run docker run --rm --network=none "$IMAGE" pwd
  [ "$output" = "/work" ]
}

@test "final: every docker build of Dockerfile.final disables networking" {
  # Grepping the whole Makefile for --network=none proves nothing: half a
  # dozen unrelated recipes already contain that string, so deleting it from
  # the stage-3 build would still pass. Ask make what the recipes actually are,
  # join their line continuations, and require the flag on the SPECIFIC
  # commands that build Dockerfile.final.
  #
  # BOTH targets are checked. add-vitis is not a prerequisite of final -- it
  # sits on the other branch of the graph -- so `make -n final` never prints
  # the variant's copy of the stage-3 build, which is the copy most likely to
  # drift because it is edited less often.
  local root="$BATS_TEST_DIRNAME/../.."
  local tgt joined total offline checked=0
  for tgt in final add-vitis; do
    # add-vitis does not exist until Task 15. `final` always must.
    if ! make -n -C "$root" "$tgt" >/dev/null 2>&1; then
      [ "$tgt" = "add-vitis" ]
      echo "skip $tgt: target not defined yet (added in Task 15)"
      continue
    fi
    run make -n -C "$root" "$tgt"
    [ "$status" -eq 0 ]
    joined="$(printf '%s\n' "$output" | sed -e :a -e '/\\$/N; s/\\\n//; ta')"
    total="$(printf '%s\n' "$joined" | grep -cF 'docker/Dockerfile.final' || true)"
    offline="$(printf '%s\n' "$joined" | grep -F 'docker/Dockerfile.final' \
               | grep -cF -- '--network=none' || true)"
    echo "$tgt: $total build(s) of Dockerfile.final, $offline offline"
    [ "$total" -ge 1 ]
    [ "$total" = "$offline" ]
    checked=$(( checked + 1 ))
  done
  # Once the Vitis target exists, skipping it is no longer acceptable -- this
  # is what stops the skip above from quietly becoming permanent.
  if grep -q '^add-vitis:' "$root/Makefile"; then
    [ "$checked" = "2" ]
  else
    [ "$checked" = "1" ]
  fi
}
