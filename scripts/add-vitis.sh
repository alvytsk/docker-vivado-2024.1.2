#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${REPO_ROOT_OVERRIDE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DOCKER="${DOCKER:-docker}"
# Required, no default: a stale default reports "the base ISO is missing"
# instead of "you did not say where the media is".
: "${MEDIA_DIR:?is not set: name the directory holding the two AMD ISOs}"
FROM_IMAGE="${RAW_IMAGE:-vivado-tools:2024.1.2-raw}"
RAW_OUT="${VITIS_RAW_IMAGE:-vivado-vitis:2024.1.2-raw}"
CONTAINER="${CONTAINER:-vivado-add-vitis}"
CONFIG="${REPO_ROOT}/config/add_config.vitis.txt"
BASE_ISO="Xilinx_Unified_2024_1_0522_2023.iso"
UPDATE_ISO="Xilinx_Vivado_Vitis_Update_2024_1_2_0906_0624.iso"

"$DOCKER" rm -f "$CONTAINER" >/dev/null 2>&1 || true

# Add Vitis from the BASE media, then apply the 2024.1.2 update AGAIN.
# The base ISO ships 2024.1; without the second step the image would contain
# a 2024.1 Vitis beside a 2024.1.2 Vivado -- a mismatched toolchain that the
# version assertion must be strict enough to catch.
# shellcheck disable=SC2016
# The single quotes are deliberate and load-bearing: everything inside runs in
# the CONTAINER, so $HOME, $DEST and friends must reach it unexpanded and be
# evaluated there. Switching to double quotes -- what SC2016 suggests -- would
# expand them on the host, where they mean something else or nothing at all.
# The two ISO names are the sole exception and are spliced in explicitly below.
"$DOCKER" run --name "$CONTAINER" --privileged --network=none \
  -v "${MEDIA_DIR}:/media:ro" \
  -v "${CONFIG}:/mnt/build/add_config.txt:ro" \
  -v "${REPO_ROOT}/lib/installer.sh:/mnt/build/installer.sh:ro" \
  "$FROM_IMAGE" bash -c '
    set -euo pipefail
    # Same HOME as stage 2 and as every discovery command in Task 2. xsetup
    # reads the install record from $HOME/.Xilinx; with a different HOME,
    # `-b Add` cannot see that Vivado is already installed and the log paths
    # below point at nothing.
    export HOME=/root
    # Scratch goes where this script deletes it, matching stage 2.
    mkdir -p /tmp/xinstall
    export TMPDIR=/tmp/xinstall
    # Same recorded command form as stage 2. Hardcoding the invocation here
    # is how the default image ends up working while Vitis silently fails.
    source /mnt/build/installer.sh
    # .xinstall is what `xsetup -b Add` reads to learn what is already
    # installed. If this fails, stage-2 cleanup deleted too much.
    test -d /tools/Xilinx/.xinstall || {
      echo "ERROR: /tools/Xilinx/.xinstall missing; -b Add cannot run" >&2
      exit 1
    }
    mkdir -p /mnt/iso

    mount -o loop,ro /media/'"$BASE_ISO"' /mnt/iso
    xsetup_add /mnt/iso/xsetup /mnt/build/add_config.txt
    umount /mnt/iso

    mount -o loop,ro /media/'"$UPDATE_ISO"' /mnt/iso
    xsetup_update /mnt/iso/xsetup /mnt/build/add_config.txt
    umount /mnt/iso

    test -f /tools/Xilinx/Vitis/2024.1/settings64.sh || {
      echo "ERROR: Vitis settings64.sh absent after Add" >&2
      exit 1
    }

    # Same rule as stage 2: prune in the stage that created the scratch, and
    # prune every path Task 2 recorded -- not just the convenient one.
    mkdir -p /var/log/xinstall
    find /root/.Xilinx/xinstall /tmp -maxdepth 2 -name "*.log" \
      -exec cp -f {} /var/log/xinstall/ \; 2>/dev/null || true
    rm -rf /root/.Xilinx/xinstall /tmp/xinstall
  '

# Reset CMD/ENTRYPOINT. This container's CMD is the whole inline install
# script above -- `docker commit` copies it verbatim into the image config,
# so a bare `docker run vivado-vitis:2024.1.2-raw` would re-run the Vitis
# install, `rm -rf` lines and all, against media that is no longer mounted.
"$DOCKER" commit \
  --change 'ENTRYPOINT []' \
  --change 'CMD ["bash"]' \
  "$CONTAINER" "$RAW_OUT"
"$DOCKER" rm -f "$CONTAINER" >/dev/null 2>&1 || true
echo "add-vitis: committed ${RAW_OUT}"
