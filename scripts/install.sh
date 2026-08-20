#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${REPO_ROOT_OVERRIDE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/buildkey.sh
source "${REPO_ROOT}/lib/buildkey.sh"

DOCKER="${DOCKER:-docker}"
# Required, no default: a stale default reports "the base ISO is missing"
# instead of "you did not say where the media is".
: "${MEDIA_DIR:?is not set: name the directory holding the two AMD ISOs}"
DEST="${DEST:-/tools/Xilinx}"
BASE_IMAGE="${BASE_IMAGE:-vivado-base:22.04}"
RAW_IMAGE="${RAW_IMAGE:-vivado-tools:2024.1.2-raw}"
CONTAINER="${CONTAINER:-vivado-install}"
CONFIG="${CONFIG:-${REPO_ROOT}/config/install_config.vivado.txt}"
HASHES="${HASHES:-${REPO_ROOT}/config/media.sha256}"
BASE_ISO="Xilinx_Unified_2024_1_0522_2023.iso"
UPDATE_ISO="Xilinx_Vivado_Vitis_Update_2024_1_2_0906_0624.iso"

REQUIRED_FREE_GB="${REQUIRED_FREE_GB:-200}"

# Uses the already-built base image, not a bare `alpine`: pulling an unpinned
# helper would contradict "only stage 1 may use the network", and --network=none
# makes that impossible rather than merely unlikely.
#
# Measure the CONTAINER'S OWN WRITABLE LAYER, not a bind-mounted host path.
#
# The obvious implementation -- ask the daemon for DockerRootDir and bind-mount
# it -- is wrong whenever the daemon does not share this filesystem. Under
# Docker Desktop (WSL2, and equally on macOS or any remote DOCKER_HOST) the
# daemon lives in its own VM: /var/lib/docker here is an empty stub on the
# local root, the bind mount resolves to THAT, and df cheerfully reports the
# free space of a disk the install will never touch. Measured on this machine,
# the two disagreed by 20 GB and only the container's own layer tracked the
# install's writes.
#
# A container's writable layer is by definition on the storage driver's
# filesystem -- exactly where stage 2 puts its ~37 GB of diff -- so `df /`
# inside a throwaway container is the one measurement that is correct on every
# topology, with no host paths and nothing to guess.
free_gb() {
  if [[ -n "${FREE_GB:-}" ]]; then printf '%s\n' "$FREE_GB"; return 0; fi
  "$DOCKER" run --rm --network=none "$BASE_IMAGE" \
    df -BG / | awk 'NR==2 {gsub(/G/,"",$4); print $4}'
}

# The base image's CONTENT, not its Id.
#
# Under BuildKit (Docker 23+, and unconditionally in 29) every `docker build`
# attaches a provenance attestation, so rebuilding the base from byte-identical
# inputs yields a DIFFERENT image Id each time. Keying on .Id therefore made the
# key unstable by construction: `install` depends on `base`, `base` rebuilds and
# re-stamps the Id, the key never matches, and every single `make install`
# started a fresh multi-hour reinstall. The reuse path could not have worked.
#
# .RootFS.Layers is the content-addressed layer chain. It is identical across
# rebuilds of identical content, and it still changes if the base genuinely
# changes -- including someone re-tagging a different image as $BASE_IMAGE,
# which is the case hashing Dockerfile.base alone would miss. Same safety,
# no false churn.
base_id="$("$DOCKER" image inspect -f '{{json .RootFS.Layers}}' "$BASE_IMAGE" 2>/dev/null || echo "absent")"
vars="MEDIA_DIR=${MEDIA_DIR} DEST=${DEST} BASE_IMAGE=${BASE_IMAGE} RAW_IMAGE=${RAW_IMAGE} CONTAINER=${CONTAINER}"

# Every host-side input that can change what stage 2 produces goes in the
# manifest -- not just the in-container script. install.sh owns the mounts,
# the environment and the commit, so omitting it would let orchestration
# change while the key stayed put. lib/installer.sh is in here for the same
# reason and is the easiest one to forget: it holds the actual xsetup argv,
# so correcting the recorded `-b Update` form must invalidate a raw image
# that was built with the wrong one -- otherwise the fix is reported as a
# cache hit and never applied.
#
# Each component is computed and checked SEPARATELY. Wrapping all three calls
# in one `$( ... )` would report only the status of the last one: a missing
# base ISO followed by a present update ISO would produce a short manifest, a
# perfectly valid-looking key, and a multi-hour install against media that is
# not there. Concatenate only after every part has succeeded.
if ! files_part="$(
      bk_manifest "$HASHES" "$base_id" "$vars" \
        "$CONFIG" \
        "${REPO_ROOT}/scripts/container-install.sh" \
        "${REPO_ROOT}/lib/installer.sh" \
        "${REPO_ROOT}/scripts/install.sh" \
        "${REPO_ROOT}/docker/Dockerfile.base")"; then
  echo "ERROR: cannot compute the stage-2 build key from the repo inputs" >&2
  exit 1
fi
if ! base_part="$(bk_media_record "${MEDIA_DIR}/${BASE_ISO}" "$HASHES")"; then
  exit 1   # bk_media_record already named the file on stderr
fi
if ! update_part="$(bk_media_record "${MEDIA_DIR}/${UPDATE_ISO}" "$HASHES")"; then
  exit 1
fi
manifest="${files_part}"$'\n'"${base_part}"$'\n'"${update_part}"
key="$(printf '%s' "$manifest" | bk_key)"
mode="$(bk_mode "$HASHES")"

if [[ "${PRINT_KEY_ONLY:-0}" == "1" ]]; then
  printf '%s\n' "$key"
  exit 0
fi

existing="$("$DOCKER" image inspect -f '{{index .Config.Labels "build.key"}}' "$RAW_IMAGE" 2>/dev/null || true)"
if [[ -n "$existing" && "$existing" == "$key" ]]; then
  echo "install: ${RAW_IMAGE} is current (key ${key:0:12}, mode ${mode}); reusing"
  exit 0
fi
[[ -n "$existing" ]] && echo "install: build key changed; rebuilding stage 2"

# Pre-flight runs only on a cache MISS. Checking it earlier would refuse a
# perfectly current image simply because the completed install itself pushed
# free space below the threshold -- breaking the fast-reuse path in Task 10.
avail="$(free_gb)"
if [[ -n "$avail" && "$avail" -lt "$REQUIRED_FREE_GB" ]]; then
  echo "ERROR: only ${avail}G free on the docker volume, need ${REQUIRED_FREE_GB}G" >&2
  echo "       override with REQUIRED_FREE_GB=<n> if you know better" >&2
  exit 1
fi

"$DOCKER" rm -f "$CONTAINER" >/dev/null 2>&1 || true

set +e
# Build scaffolding is mounted under /mnt/build, NOT into /usr/local.
# A bind-mounted file leaves a ZERO-BYTE STUB at its mount point in the
# committed image -- Docker creates the mount point, `docker commit` records
# it, and the content never was part of the filesystem. Mounting the library
# at /usr/local/lib/installer.sh therefore ships an empty file at a path that
# reads like the real library, in both the raw and the final image. Under
# /mnt/build the leftovers are unmistakably build scaffolding.
"$DOCKER" run --name "$CONTAINER" --privileged --network=none \
  -v "${MEDIA_DIR}:/media:ro" \
  -v "${REPO_ROOT}/scripts/container-install.sh:/mnt/build/container-install.sh:ro" \
  -v "${REPO_ROOT}/lib/installer.sh:/mnt/build/installer.sh:ro" \
  -v "${CONFIG}:/mnt/build/install_config.txt:ro" \
  -e "MEDIA_DIR=/media" -e "DEST=${DEST}" -e "CONFIG=/mnt/build/install_config.txt" \
  -e "INSTALLER_LIB=/mnt/build/installer.sh" \
  "$BASE_IMAGE" bash /mnt/build/container-install.sh
rc=$?
set -e

if [[ $rc -ne 0 ]]; then
  echo "install: stage 2 failed (rc=$rc); extracting installer logs" >&2
  "$DOCKER" cp "${CONTAINER}:/var/log/xinstall" ./build-logs 2>/dev/null || true
  "$DOCKER" rm -f "$CONTAINER" >/dev/null 2>&1 || true
  exit $rc
fi

# CMD and ENTRYPOINT must be reset explicitly. `docker commit` inherits the
# CONTAINER's config, so without these the raw image's CMD is
# ["bash","/mnt/build/container-install.sh"] -- a path that exists in the
# image only as a zero-byte stub. `docker run vivado-tools:2024.1.2-raw`
# would then exit 0 having silently done nothing, which is a worse failure
# than an error. (add-vitis.sh has the same problem in a sharper form: its
# container CMD is the entire inline install script.)
"$DOCKER" commit \
  --change "LABEL build.key=${key}" \
  --change "LABEL build.key.mode=${mode}" \
  --change 'ENTRYPOINT []' \
  --change 'CMD ["bash"]' \
  "$CONTAINER" "$RAW_IMAGE"
"$DOCKER" rm -f "$CONTAINER" >/dev/null 2>&1 || true
echo "install: committed ${RAW_IMAGE} (key ${key:0:12}, mode ${mode})"
