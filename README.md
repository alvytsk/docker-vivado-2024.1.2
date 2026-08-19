# Vivado ML Standard 2024.1.2 — headless Docker image

A headless AMD/Xilinx Vivado ML Standard 2024.1.2 image for CI. You bind-mount a
design repository at `/work`, run `vivado -mode batch -source <your>.tcl`, and get
`.bit` and `.xsa` artifacts back, owned by the invoking host user. There is no GUI,
no X server, no Xilinx account and no license file anywhere in the build.

The image is built from two locally held AMD ISOs (the 2024.1 Unified base and the
2024.1.2 update). Nothing is downloaded from AMD at any point.

## Supported devices

Vivado ML **Standard** covers exactly seven Zynq-7000 parts, and this image installs
the Zynq-7000 device family only:

| | |
|---|---|
| XC7Z007S | XC7Z010 |
| XC7Z012S | XC7Z014S |
| XC7Z015 | XC7Z020 |
| XC7Z030 | |

### XC7Z035, XC7Z045 and XC7Z100 cannot be built with this image

They are Zynq-7000 parts, so their **device data is installed** and the tools will
happily accept them: you can create a project, open a block design and elaborate.
The limit is enforced by *licensing at tool runtime*, so the failure arrives late —
synthesis stops with an AMD licensing error. These three parts require a paid
Enterprise license and are deliberately out of scope. This is documented rather
than worked around.

`test/integration/device-scope.bats` pins that boundary down as observable
behaviour: it asserts that XC7Z020 synthesises, that the XC7Z045 *part data* is
present (so a failure cannot be blamed on a missing part), and that XC7Z045 then
fails with a licensing diagnostic specifically.

## Licensing

**The image ships no license file and needs none.** Vivado ML Standard is
license-free for the seven-part subset above. `XILINXD_LICENSE_FILE` is left unset,
and `test/integration/final.bats` asserts the image contains no `.lic` file.

If you nonetheless want to supply a license — because you have an Enterprise seat and
want XC7Z045 — the runtime hook is already there, with no image change required:

```bash
# floating license server
docker run --rm --init -e XILINXD_LICENSE_FILE=port@host ... vivado:2024.1.2 ...

# or a node-locked file, bind-mounted into $HOME/.Xilinx
docker run --rm --init -v /path/to/Xilinx.lic:/home/vivado/.Xilinx/Xilinx.lic:ro ... vivado:2024.1.2 ...
```

`$HOME` is always `/home/vivado` unless that directory is unwritable, in which case
the entrypoint falls back to a fresh directory under `/tmp` — see *File ownership*.

## Quick start

```bash
make build

docker run --rm --init -v "$PWD:/work" -e HOST_UID=$(id -u) -e HOST_GID=$(id -g) vivado:2024.1.2 vivado -mode batch -source build.tcl
```

`make build` runs stage 1 (`docker build` of the base image), stage 2 (the install,
which is the multi-hour step) and stage 3 (the thin runtime layer), in that order,
as real Make prerequisites.

You do not need to source `settings64.sh`. The entrypoint sources it for you, so
`vivado`, `XILINX_VIVADO` and friends are already in the environment of whatever
command you pass.

### `--init` is not optional decoration

The entrypoint ends in `exec "$@"`, so **Vivado itself becomes PID 1**. PID 1 is
responsible for reaping orphaned children, and Vivado does not do it: `launch_runs`
forks a child per synthesis and implementation job, and every one that finishes
stays in the process table as a zombie for the length of the run. `--init` puts a
real init process at PID 1 to reap them. Both `test/run-smoke.sh` and the quick-start
line above use it.

## File ownership in CI

Vivado writes into `/work` as whatever UID the container runs as, so ownership is
reconciled at *runtime*, never baked into the image. Three ways to control it, in
order of preference:

1. **`--user "$(id -u):$(id -g)"`** — preferred in CI. The entrypoint detects it is
   already non-root, skips reconciliation entirely, and just sets `HOME` and execs.
2. **`-e HOST_UID=... -e HOST_GID=...`** — the entrypoint starts as root, appends a
   `/etc/passwd`/`/etc/group` record if that ID is absent, and drops privileges with
   numeric `gosu`. Arbitrary IDs work, including ones that collide with `nobody`.
3. **Neither** — the IDs are inferred from the numeric owner of `/work`.

A resolved ID of `0` is treated as "no usable hint", never as an instruction: an
explicit `HOST_UID=0` and a root-owned `/work` both fall back to the built-in
`1000:1000`, rather than remapping the tool to root. `HOME` is exported explicitly
in *both* branches — `gosu` execs without building a login environment, so an
inherited `HOME=/root` would be unwritable and would silently break Vivado's user
data directory and the `~/.Xilinx` licensing hook.

## Build key — when stage 2 re-runs

Stage 2 is a `docker run` plus `docker commit`, not a `docker build`, so Docker's own
layer cache cannot see it. Reuse of `vivado-tools:2024.1.2-raw` is gated on an
explicit build key instead: the SHA-256 of a manifest covering the base image ID,
`config/install_config.vivado.txt`, `scripts/container-install.sh`,
`lib/installer.sh`, `scripts/install.sh`, `docker/Dockerfile.base`, the Make
variables that reach stage 2, and an identity record per ISO. The key and the mode
that produced it are stamped on the raw image as the `build.key` and
`build.key.mode` labels; `install.sh` reuses the image only on an exact match.

**Default media identity is size and mtime, not content.** Hashing 164 GB of ISO
across the WSL drvfs boundary costs ten to twenty minutes on *every* build,
including the ones the key check exists to make free. So:

- Default (`metadata` mode): an ISO is identified by `(name, size, mtime)`. **A
  replacement that preserves both size and mtime is not detected.**
- `make verify-media`: computes real SHA-256 for both ISOs into
  `config/media.sha256`. Once that file exists, stage 2 switches to `verified` mode,
  re-hashes on every run, and aborts on a mismatch.

## Reproducibility — what is actually claimed

Input-tracked and functionally stable, **not bit-identical**:

- The base image is pinned by digest, not tag (`ubuntu:22.04@sha256:2edbbc5d…`).
- Every AMD input and every host-side script that can change stage 2's output is
  hashed into the build key.
- **Ubuntu package versions float.** Stage 1 runs `apt-get install` against live
  mirrors, so two builds a month apart get different point releases of the X and
  ncurses libraries.

Rebuilding from the same media and the same commit gives you the same Vivado
install and the same behaviour; it does not give you the same image digest.

## Offline scope — what "no AMD network access" means

The guarantee is *no AMD network access*, not *no network access at all*:

- No connection to any `xilinx.com` or `amd.com` host, at any point.
- No Xilinx account, no `AuthTokenGen`, no web installer.
- Every byte of AMD software comes from the two local ISOs, mounted read-only.
- **Stages 2 and 3 run with `--network=none`**, which enforces the above
  mechanically rather than by intention.

Stage 1 *does* need the network — to pull the pinned Ubuntu base and install Ubuntu
packages. Neither is on the AMD media, so claiming an air-gapped build would be
false. Making stage 1 offline too would mean vendoring a base-image tarball and a
local apt repository; `install.sh` already accepts a pre-pulled base image if you
go that way.

## Vitis variant

Vitis is excluded by default: it roughly doubles the image and is not needed to
produce `.xsa` or `.bit`, only to build FSBL, `BOOT.BIN` or application ELFs.

```bash
make add-vitis     # xsetup -b Add against the same media, tags vivado-vitis:2024.1.2
make test-vitis
```

The variant reuses `docker/Dockerfile.final` unchanged, so its entrypoint, `HOME`
handling, workdir and environment are identical to the default image by
construction. The entrypoint sources the Vitis `settings64.sh` *after* Vivado's, and
only if it exists — shipping the file is not what puts `xsct` on `PATH`; sourcing
it is.

**The asymmetry matters:** adding Vitis later is cheap (a new layer on an existing
image), but *removing* it later reclaims nothing. Docker layers are additive, so an
uninstall writes whiteouts while the bytes stay in the parent layer and continue to
be pushed and pulled. Shrinking requires re-running stage 2 from scratch. That
asymmetry is precisely why the default is the smaller image.

The same rule is why `Dockerfile.final` contains no cleanup at all, and why all
installer scratch is pruned inside stage 2's container before it exits.

## Image size and distribution

Final image size: **<recorded in Task 11 Step 6>**.

This is far too large for Docker Hub in a CI loop. Use a **local or self-hosted
registry**. The two-image split is built for exactly that: the fat
`vivado-tools:2024.1.2-raw` layer changes only when the media or the install inputs
change, so runners pull it once and thereafter pull only the thin stage-3 layer.

## Make targets

| Target | What it does |
|---|---|
| `make lint` | ShellCheck (containerised, `-x`) over `lib/` and `scripts/` |
| `make test-unit` | bats unit tests (`test/unit`), no images required |
| `make base` | Stage 1 — `vivado-base:22.04` |
| `make install` | Stage 2 — the install; commits `vivado-tools:2024.1.2-raw` |
| `make verify-media` | Record real SHA-256 of both ISOs; switches the key to verified mode |
| `make final` / `make build` | Stage 3 — `vivado:2024.1.2` |
| `make test-integration` | bats integration tests against the built image |
| `make test-smoke` / `make test` | `test/run-smoke.sh` — full block design flow in every identity mode |
| `make add-vitis` | Adds Vitis, tags `vivado-vitis:2024.1.2` |
| `make test-vitis` | bats tests for the Vitis variant |
| `make test-all` | `lint test-unit test-integration test-smoke` — default-image sweep for development |
| `make acceptance` | The full sweep, including the Vitis variant, from freshly built images |

`test-all` is *not* an acceptance run: it never exercises the Vitis variant, so on a
clean machine it either fails or — worse — passes only because an earlier manual
step left images lying around. Use `make acceptance` for the real thing. Both chain
their prerequisites as real Make dependencies, so `make -j` cannot build the final
image before stage 2 has produced the raw image it is `FROM`.

## Acceptance criteria mapping

The nine criteria in section 13 of the design spec, and where each is exercised.
(Listed as coverage, not as a claim of results.)

| # | Criterion | Exercised by |
|---|---|---|
| 1 | `make build` from a clean state, no Xilinx account, stages 2–3 under `--network=none` | `make build`; `test/unit/install.bats` ("runs stage 2 with `--network=none`", "mounts the media read-only"); `test/integration/final.bats` ("every docker build of Dockerfile.final disables networking") |
| 2 | `vivado -version` reports 2024.1.2, not the un-updated 2024.1 | `make test-integration` → `test/integration/final.bats` ("vivado reports 2024.1.2") |
| 3 | `make test` runs `test/zynq_smoke.tcl` end to end and produces non-empty `.bit` and `.xsa` in a bind-mounted `/work` | `make test` / `make test-smoke` → `test/run-smoke.sh` + `test/zynq_smoke.tcl` |
| 4 | No license error in the smoke run, and no `.lic` in the image | `test/run-smoke.sh` (licensing-pattern grep over the run output); `test/integration/final.bats` ("image contains no license file") |
| 5 | `/work` artifacts owned by the invoking UID, verified at a **non-1000** UID, via `HOST_UID`, via `--user`, and via `/work`-owner inference | `test/run-smoke.sh` (`hostenv` and `user` modes at 1234, plus the invoking user); `test/integration/identity.bats` cases 1–3 |
| 6 | `echo $XILINX_VIVADO` resolves without the caller sourcing anything | `test/integration/final.bats` ("XILINX_VIVADO resolves without the caller sourcing anything") |
| 7 | XC7Z045 fails with a recognisable licensing error, not a tool crash; README names the three unsupported parts | `test/integration/device-scope.bats` (all three tests); *Supported devices* above |
| 8 | In the no-bind-mount case: `id -u` non-zero, `$HOME` not `/root`, `test -w "$HOME"` succeeds — all in one invocation | `test/integration/identity.bats` ("HOME is set, writable, and never /root (criterion 8)", plus the no-mount and root-owned-`/work` cases) |
| 9 | `make add-vitis` succeeds and `xsct -eval "puts [version]"` answers 2024.1.2 headlessly with `XILINX_VITIS` set | `make test-vitis` → `test/vitis/` |

## Installer facts this build depends on

Captured against the real media in `docs/installer-facts.md`, by running the ISOs
offline. Two of them shape the build directly:

- **The batch invocations are recorded once, in `lib/installer.sh`, and never
  inlined anywhere else:** `xsetup -a XilinxEULA,3rdPartyEULA -b Install -c <config>`,
  the same form with `-b Add`, and the same form with `-b Update`. `-b Update`
  accepts and validates `-c` (a missing file is rejected by name) while `-l` changes
  nothing — the update finds the installation itself. The update media cannot
  generate a config of its own, so the Update config comes from the base media.
- **`xsetup` ignores `TMPDIR`.** Setting it changes nothing: the installer writes to
  `$HOME/.Xilinx` (containing `registry/` and `xinstall/`, i.e. `/root/.Xilinx` when
  the install runs as root) and to `/tmp/hsperfdata_root` from its bundled JVM
  regardless. Those scratch paths therefore have to be **deleted by name**, inside
  stage 2, before the container exits — which is what `SCRATCH_DIR` / `SCRATCH_EXTRA`
  in `scripts/container-install.sh` do. `$HOME` is pinned during the install for the
  same reason: it is what selects that directory.

`/tools/Xilinx/.xinstall` looks exactly like installer scratch and is **not**. It is
the installer's record of what it installed, and both `-b Add` and `-b Update` read
it; deleting it would leave a working Vivado image in which the Vitis path and any
future update silently cannot run. It is explicitly preserved through cleanup, and
`test/unit/container-install.bats` asserts that it is never removed — not even by
pattern.

Installer logs are copied to `/var/log/xinstall/` inside the image (they are small,
and retained deliberately so a later support question is answerable from the image
itself). If stage 2 fails, `scripts/install.sh` copies them out to `./build-logs`
on the host before removing the container.
