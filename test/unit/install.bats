#!/usr/bin/env bats

load helpers

setup() {
  TMP="$(mktemp -d)"
  mkdir -p "$TMP/media" "$TMP/bin"
  printf 'base'   > "$TMP/media/Xilinx_Unified_2024_1_0522_2023.iso"
  printf 'update' > "$TMP/media/Xilinx_Vivado_Vitis_Update_2024_1_2_0906_0624.iso"
  export DOCKER_LOG="$TMP/docker.log"
  cat > "$TMP/bin/docker" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$DOCKER_LOG"
case "$1 $2" in
  "image inspect")
    if [[ "$*" == *"vivado-tools"* && -n "${FAKE_RAW_KEY:-}" ]]; then
      echo "$FAKE_RAW_KEY"; exit 0
    fi
    if [[ "$*" == *"vivado-base"* ]]; then echo "sha256:baseid"; exit 0; fi
    exit 1 ;;
esac
exit 0
EOF
  chmod +x "$TMP/bin/docker"
}

teardown() { rm -rf "$TMP"; }

run_install() {
  MEDIA_DIR="$TMP/media" DOCKER="$TMP/bin/docker" \
  REPO_ROOT_OVERRIDE="$REPO_ROOT" \
  run bash "$REPO_ROOT/scripts/install.sh"
}

@test "install fails fast and names the path when media is missing" {
  rm -f "$TMP/media/Xilinx_Unified_2024_1_0522_2023.iso"
  run_install
  [ "$status" -ne 0 ]
  [[ "$output" == *"Xilinx_Unified_2024_1_0522_2023.iso"* ]]
}

@test "a missing BASE iso is not masked by a present UPDATE iso" {
  # The base record is emitted BEFORE the update record. If the manifest is
  # assembled in one command substitution, the update's success overwrites the
  # base's failure and the install proceeds against media that is not there.
  rm -f "$TMP/media/Xilinx_Unified_2024_1_0522_2023.iso"
  run_install
  [ "$status" -ne 0 ]
  run grep -c 'run --name' "$DOCKER_LOG"
  [ "$output" = "0" ]
}

@test "install fails when a build-key input file is missing" {
  # Same masking hazard one level down, inside bk_manifest.
  cp -a "$REPO_ROOT" "$TMP/repo"
  rm -f "$TMP/repo/docker/Dockerfile.base"
  MEDIA_DIR="$TMP/media" DOCKER="$TMP/bin/docker" \
  REPO_ROOT_OVERRIDE="$TMP/repo" \
  run bash "$TMP/repo/scripts/install.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Dockerfile.base"* ]]
}

@test "install runs stage 2 with --network=none and --privileged" {
  run_install
  run grep -E 'run .*--privileged' "$DOCKER_LOG"
  [ "$status" -eq 0 ]
  run grep -E 'run .*--network=none' "$DOCKER_LOG"
  [ "$status" -eq 0 ]
}

@test "install mounts the media read-only" {
  run_install
  run grep -E "\-v $TMP/media:/media:ro" "$DOCKER_LOG"
  [ "$status" -eq 0 ]
}

@test "install mounts lib/installer.sh where container-install.sh sources it" {
  # The base image does not contain the library; container-install.sh sources
  # INSTALLER_LIB unconditionally. Without this mount stage 2 dies on line
  # one -- hours of media mounting away from anything useful.
  run_install
  run grep -F "installer.sh:/mnt/build/installer.sh:ro" "$DOCKER_LOG"
  [ "$status" -eq 0 ]
}

@test "install keeps build scaffolding out of /usr/local" {
  # Bind mounts leave zero-byte stubs at their mount points in the committed
  # image. An empty /usr/local/lib/installer.sh is indistinguishable from the
  # real library to anyone reading the image.
  run_install
  run grep -E '\-v [^ ]*:/usr/local/' "$DOCKER_LOG"
  [ "$status" -ne 0 ]
}

@test "install resets CMD and ENTRYPOINT when committing the raw image" {
  # docker commit inherits the container config. Without these the raw image
  # runs a zero-byte stub as its default command.
  run_install
  run grep -F 'CMD ["bash"]' "$DOCKER_LOG"
  [ "$status" -eq 0 ]
  run grep -F 'ENTRYPOINT []' "$DOCKER_LOG"
  [ "$status" -eq 0 ]
}

@test "editing lib/installer.sh changes the build key" {
  local before after
  before="$(MEDIA_DIR="$TMP/media" DOCKER="$TMP/bin/docker" \
            REPO_ROOT_OVERRIDE="$REPO_ROOT" PRINT_KEY_ONLY=1 \
            bash "$REPO_ROOT/scripts/install.sh")"
  # Mutate a copy of the repo rather than the repo itself.
  cp -a "$REPO_ROOT" "$TMP/repo"
  echo '# changed update form' >> "$TMP/repo/lib/installer.sh"
  after="$(MEDIA_DIR="$TMP/media" DOCKER="$TMP/bin/docker" \
           REPO_ROOT_OVERRIDE="$TMP/repo" PRINT_KEY_ONLY=1 \
           bash "$TMP/repo/scripts/install.sh")"
  [ "$before" != "$after" ]
}

@test "install commits with a build.key label" {
  run_install
  run grep -E 'commit .*build\.key=' "$DOCKER_LOG"
  [ "$status" -eq 0 ]
}

@test "install records the key mode as metadata by default" {
  run_install
  run grep -E 'build\.key\.mode=metadata' "$DOCKER_LOG"
  [ "$status" -eq 0 ]
}

@test "install reuses the raw image when the key matches" {
  local key
  key="$(MEDIA_DIR="$TMP/media" DOCKER="$TMP/bin/docker" \
         REPO_ROOT_OVERRIDE="$REPO_ROOT" PRINT_KEY_ONLY=1 \
         bash "$REPO_ROOT/scripts/install.sh")"
  FAKE_RAW_KEY="$key" run_install
  [ "$status" -eq 0 ]
  run grep -c 'commit' "$DOCKER_LOG"
  [ "$output" = "0" ]
}

@test "the build key does not depend on the base image Id" {
  # BuildKit stamps a new image Id on every build (provenance attestation), so
  # a key derived from .Id can never match on the second run and every
  # `make install` restarts a multi-hour reinstall. The key must come from the
  # content-addressed layer chain instead. Guard the mechanism, not the value:
  # assert install.sh never inspects .Id.
  run grep -n "image inspect -f '{{.Id}}'" "$REPO_ROOT/scripts/install.sh"
  [ "$status" -ne 0 ]
  run grep -F 'RootFS.Layers' "$REPO_ROOT/scripts/install.sh"
  [ "$status" -eq 0 ]
}

@test "install rebuilds when the stored key differs" {
  FAKE_RAW_KEY="stale-key" run_install
  [ "$status" -eq 0 ]
  run grep -c 'commit' "$DOCKER_LOG"
  [ "$output" != "0" ]
}

@test "install refuses to start when free space is below the threshold" {
  MEDIA_DIR="$TMP/media" DOCKER="$TMP/bin/docker" \
  REPO_ROOT_OVERRIDE="$REPO_ROOT" FREE_GB=10 REQUIRED_FREE_GB=200 \
  run bash "$REPO_ROOT/scripts/install.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"free"* ]]
  run grep -c 'run --name' "$DOCKER_LOG"
  [ "$output" = "0" ]
}

@test "install does NOT refuse a current image just because space is now low" {
  # Reuse must win over the space check: a completed install legitimately
  # consumes the space the threshold is guarding.
  local key
  key="$(MEDIA_DIR="$TMP/media" DOCKER="$TMP/bin/docker" \
         REPO_ROOT_OVERRIDE="$REPO_ROOT" PRINT_KEY_ONLY=1 \
         bash "$REPO_ROOT/scripts/install.sh")"
  FAKE_RAW_KEY="$key" MEDIA_DIR="$TMP/media" DOCKER="$TMP/bin/docker" \
  REPO_ROOT_OVERRIDE="$REPO_ROOT" FREE_GB=10 REQUIRED_FREE_GB=200 \
  run bash "$REPO_ROOT/scripts/install.sh"
  [ "$status" -eq 0 ]
}

@test "install proceeds when free space is sufficient" {
  MEDIA_DIR="$TMP/media" DOCKER="$TMP/bin/docker" \
  REPO_ROOT_OVERRIDE="$REPO_ROOT" FREE_GB=900 REQUIRED_FREE_GB=200 \
  run bash "$REPO_ROOT/scripts/install.sh"
  [ "$status" -eq 0 ]
}

@test "install removes a stale container of the same name before starting" {
  run_install
  run grep -E '^rm -f vivado-install' "$DOCKER_LOG"
  [ "$status" -eq 0 ]
}
