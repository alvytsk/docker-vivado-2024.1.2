# Installer facts (captured 2026-08-18)

All output below was produced by running the real AMD media offline
(`--network=none`, ISOs loop-mounted read-only inside
`ubuntu:22.04@sha256:2edbbc5dc405e9612ba3584ce95480277e3eb374407b5505fe26f17df77c7dbc`).
The installer produced its help and its ConfigGen output with no network at all,
so neither step needs one.

## Base ISO — confirmed
Batch actions: AuthTokenGen, ConfigGen, Install, Uninstall, Add, Update.
Install invocation: `xsetup -a XilinxEULA,3rdPartyEULA -b Install -c <config>`

Valid product names, quoted from the installer itself
(`xsetup -b ConfigGen -p Bogus` on `Xilinx_Unified_2024_1_0522_2023.iso`):

```
ERROR - The value specified for Product (Bogus) is invalid. Valid product names are "Vitis","Vivado","Vitis Embedded Development","BootGen","Lab Edition","Hardware Server","Power Design Manager (PDM)","On-Premises Install for Cloud Deployments","PetaLinux","Documentation Navigator (Standalone)". Please specify a valid product name using -p <product name> or point to an install configuration file using -c <filename>.
```

## Update ISO — `-b Update` argument form

`/m/xsetup --help` on `Xilinx_Vivado_Vitis_Update_2024_1_2_0906_0624.iso`
(`/tmp/update-xsetup-help.txt`) — the update media prints the same option set as
the base media, and there is no Update-specific flag:

```
usage: xsetup [-a <arg>] [-b <arg>] [-c <arg>] [-e <arg>] [-h] [-l <arg>]
       [-p <arg>] [-x]
AMD Installer for FPGAs & Adaptive SoCs - Command line argument list.
 -a,--agree <arg>      Agree to the required terms and conditions.
                       [XilinxEULA,3rdPartyEULA]
 -b,--batch <arg>      Runs installer in batch mode and executes the
                       specified action. Valid actions are [AuthTokenGen,
                       ConfigGen, Install, Uninstall, Add, Update].
                       AuthTokenGen is used to generate an authentication
                       token that will be used by the batch mode
                       webinstaller to download install content. ConfigGen
                       is used to generate a config file as described
                       below. Install is use for a fresh installation.
                       Uninstall is for uninstalling an existing
                       installation. Add is for adding tools or devices to
                       an existing installation. Update is for installing
                       an update release from AMD.
 -c,--config <arg>     File defining install configuration. It is
                       recommended to use a configuration file for batch
                       install. To generate a configuration file, run
                       xsetup -b ConfigGen. This file will contain the
                       default install selections, which you can then
                       change as needed by setting a value to 1(select) or
                       0(de-select) within the file. It is recommended
                       that you generate this reference for each new
                       quarterly release, so that new devices, tools,
                       options or other changes will be accounted for in
                       your configuration file.
 -e,--edition <arg>    Name of the edition that should be installed. This
                       option is not needed if using -c with a config file
                       since the edition is included in the config file.
 -h,--help             Display this help text.
 -l,--location <arg>   The destination location of the installation. This
                       option is not needed if using -c with a config file
                       since the location is included in the config file.
 -p,--product <arg>    Name of the product that should be installed. This
                       option is not needed if using -c with a config file
                       since the product is included in the config file.
 -x,--xdebug           Run installer in debug mode


Examples:

Generate authentication token: xsetup -b AuthTokenGen

Generate a config file: xsetup -b ConfigGen  (generate and modify as
needed).

Install using a config file: xsetup -a XilinxEULA,3rdPartyEULA -b Install
-c install_config.txt.

If you do not wish to use a config file, you must provide the -l and -e.
The -e choices for a given release can be found by generating a config
file and copying the edition name from the resulting config file. When you
do not use a config file, the default install options will be used for
your installation.

Example installing without a config file: xsetup --agree
3rdPartyEULA,XilinxEULA --batch Install --product "Vitis" --edition "Vitis
Unified Software Platform" --location "C:\Xilinx".

The batch mode also supports uninstallation and upgrades (adding
additional tools and devices). For example, if you install the AMD FPGAs &
Adaptive SoCs software to <user home>/Xilinx, go to <user
home>/Xilinx/.xinstall/<product>_<version>

To uninstall: xsetup -b Uninstall.
For GUI mode uninstallation: xsetup -Uninstall.

To add devices or tools: xsetup -b Add -a XilinxEULA,3rdPartyEULA -c
<configfile>.
```

The update media cannot generate a config of its own. `-b ConfigGen` there fails
in two distinct ways (`/tmp/update-configgen.txt`, `/tmp/update-configgen-diag.txt`):

```
ERROR - The value specified for Product (Vivado) is invalid. Valid product names are . Please specify a valid product name using -p <product name> or point to an install configuration file using -c <filename>.
ERROR - Could not perform an Update, could not find details about the existing installation.
```

so `-b ConfigGen` against the update ISO writes no `install_config.txt` at all —
the Update config must come from the base media, or be omitted.

Argument forms actually exercised against the update ISO with no installation
present (`/tmp/update-form-probe.txt`, `/tmp/update-form-probe2.txt`):

```
$ xsetup -a XilinxEULA,3rdPartyEULA -b Update
ERROR - Could not find a valid installation to apply the Update.

$ xsetup -a XilinxEULA,3rdPartyEULA -b Update -l /tools/Xilinx
ERROR - Could not find a valid installation to apply the Update.

$ xsetup -a XilinxEULA,3rdPartyEULA -b Update -c /nonexistent.txt
ERROR - Could not read the specified configuration file. Please check it exists and it is readable.

$ xsetup -a XilinxEULA,3rdPartyEULA -b Update -c <config generated by the base ISO>
ERROR - Could not find a valid installation to apply the Update.
```

Read together: `-c` is accepted and validated by `-b Update` (a missing file is
rejected by name, a real base-media config is read and the run advances to
locating the existing installation), while `-l` changes nothing — the Update
finds the installation itself. `-c <config>` is therefore the form that is both
accepted and unambiguous, and it is the same form as Install and Add.

**Decision:** the update is invoked as `xsetup -a XilinxEULA,3rdPartyEULA -b Update -c <config>`.

## `-b Add` and the Vitis product config

Complete config produced by `xsetup -b ConfigGen -p Vitis -e "Vitis Unified
Software Platform"` on the base ISO (`/tmp/add-semantics.txt`), verbatim:

```
#### Vitis Unified Software Platform Install Configuration ####
Edition=Vitis Unified Software Platform

Product=Vitis

# Path where AMD FPGAs & Adaptive SoCs software will be installed.
Destination=/tools/Xilinx

# Choose the Products/Devices the you would like to install.
Modules=Virtex UltraScale+ 58G:1,Install Devices for Kria SOMs and Starter Kits:1,Vitis IP Cache (Enable faster on-boarding for new users):0,Versal AI Edge Series ES1:0,Zynq-7000:1,Versal Prime Series ES1:0,Kintex UltraScale+:1,Artix UltraScale+:1,Spartan-7:1,Install devices for Alveo and edge acceleration platforms:1,Engineering Sample Devices for Custom Platforms:0,Vitis Networking P4:0,Artix-7:1,Zynq UltraScale+ MPSoC:1,Versal HBM Series ES1:0,DocNav:1,Versal HBM Series:1,Virtex UltraScale+ HBM:1,Kintex-7:1,Virtex UltraScale+:1,Versal AI Core Series:1,Versal AI Edge Series:1,Kintex UltraScale:1,Versal Premium Series:1,Virtex UltraScale:1,Versal Premium Series ES1:0,Zynq UltraScale+ RFSoC:1,Power Design Manager (PDM):0,Versal AI Core Series ES1:0,Versal Prime Series:1,Virtex-7:1,Virtex UltraScale+ HBM ES:0

# Choose the post install scripts you'd like to run as part of the finalization step. Please note that some of these scripts may require user interaction during runtime.
InstallOptions=

## Shortcuts and File associations ##
# Choose whether Start menu/Application menu shortcuts will be created or not.
CreateProgramGroupShortcuts=1

# Choose the name of the Start menu/Application menu shortcut. This setting will be ignored if you choose NOT to create shortcuts.
ProgramGroupFolder=Xilinx Design Tools

# Choose whether shortcuts will be created for All users or just the Current user. Shortcuts can be created for all users only if you run the installer as administrator.
CreateShortcutsForAllUsers=0

# Choose whether shortcuts will be created on the desktop or not.
CreateDesktopShortcuts=1

# Choose whether file associations will be created or not.
CreateFileAssociation=1

# Choose whether disk usage will be optimized (reduced) after installation
EnableDiskUsageOptimization=1
```

`xsetup -b Add --help` on the base ISO prints the general help, not an
Add-specific one (`/tmp/add-semantics.txt`, first 40 lines):

```
This is a fresh install.
INFO Could not detect the display scale (hDPI).
       If you are using a high resolution monitor, you can set the insaller scale factor like this: 
       export XINSTALLER_SCALE=2
       setenv XINSTALLER_SCALE 2
Running in batch mode...
Copyright (c) 1986-2022 Xilinx, Inc.  All rights reserved.
Copyright (c) 2022-2026 Advanced Micro Devices, Inc.  All rights reserved.

usage: xsetup [-a <arg>] [-b <arg>] [-c <arg>] [-e <arg>] [-h] [-l <arg>]
       [-p <arg>] [-x]
AMD Installer for FPGAs & Adaptive SoCs - Command line argument list.
 -a,--agree <arg>      Agree to the required terms and conditions.
                       [XilinxEULA,3rdPartyEULA]
 -b,--batch <arg>      Runs installer in batch mode and executes the
                       specified action. Valid actions are [AuthTokenGen,
                       ConfigGen, Install, Uninstall, Add, Update].
                       AuthTokenGen is used to generate an authentication
                       token that will be used by the batch mode
                       webinstaller to download install content. ConfigGen
                       is used to generate a config file as described
                       below. Install is use for a fresh installation.
                       Uninstall is for uninstalling an existing
                       installation. Add is for adding tools or devices to
                       an existing installation. Update is for installing
                       an update release from AMD.
 -c,--config <arg>     File defining install configuration. It is
                       recommended to use a configuration file for batch
                       install. To generate a configuration file, run
                       xsetup -b ConfigGen. This file will contain the
                       default install selections, which you can then
                       change as needed by setting a value to 1(select) or
                       0(de-select) within the file. It is recommended
                       that you generate this reference for each new
                       quarterly release, so that new devices, tools,
                       options or other changes will be accounted for in
                       your configuration file.
 -e,--edition <arg>    Name of the edition that should be installed. This
                       option is not needed if using -c with a config file
                       since the edition is included in the config file.
```

The only sentence anywhere in that help that describes Add is the example at the
end of the help text:

```
To add devices or tools: xsetup -b Add -a XilinxEULA,3rdPartyEULA -c
<configfile>.
```

One further behaviour was observed directly: run against a machine with *no*
existing installation, `xsetup -a XilinxEULA,3rdPartyEULA -b Add -c <the Vitis
config above>` does not refuse the way `-b Update` does — it starts installing,
and had written 99 GB into `/tools/Xilinx` (`Vivado`, `Vitis`, `Vitis_HLS`,
`Model_Composer`, `DocNav`, `SharedData`, `xic`) before the probe was stopped.
So `-b Add` treats the config's `Modules=` line as a selection to realise, not as
a diff against an existing install, which is evidence for the full-list reading —
but it does not show what happens to modules that are installed and marked `0`,
and that is the half that matters.

Nothing in it says whether the `Modules=` line handed to `-b Add` must repeat
everything already installed or list only the additions. Two observed facts make
guessing worse than deferring: the generated Vitis config already carries
`Zynq-7000:1`, and `Vitis Embedded Development` does not appear in `Modules=` at
all — the installer lists it as a *product* name, alongside "Vitis" and "Vivado".

**Decision:** resolved 2026-08-19 by experiment against the installed image --
the `-b Add` route **does not work offline at all**, so `config/add_config.vitis.txt`
is not an Add config. Four bounded experiments, each answered by the installer:

1. ISO `xsetup -b Add` with `Edition=Vivado ML Standard` →
   *"The value specified for Edition (Vivado ML Standard) is invalid. Valid
   edition names are \"Vitis Unified Software Platform\""*. The Vitis product
   has its own edition name; Vivado's config cannot be reused.
2. Same, with the corrected edition but Vivado's `Modules=` line →
   *"The value specified in the configuration file for Modules (...) is not
   valid."* Vitis has a different module set (no `Vitis Embedded Development`
   entry: with `-p Vitis` the product IS Vitis, and the list selects devices).
3. ISO `xsetup -b Add` with the correct Vitis config →
   *"An existing installation of Vivado 2024.1 has been detected at
   /tools/Xilinx. To install a new copy ... provide an alternate destination
   ... To update the current installation, use the 'Add Design Tools or
   Devices' option from the Help Menu within Vivado"*. The ISO installer
   treats the destination as occupied and points at the GUI.
4. The INSTALLED installer, `/tools/Xilinx/.xinstall/Vivado_2024.1/xsetup -b Add`
   → config **accepted**, then *"Could not connect to the internet using
   provided information."* It ignores the mounted ISO and expects to download
   the payload from AMD.

`xsetup -b Add --help` prints only the general help; there is no documented
option to point `-b Add` at local media.

**Consequence for Task 15 / spec section 10:** Vitis cannot be layered onto the
existing raw image offline. The supported offline route is a SINGLE
`-b Install` with `Edition=Vitis Unified Software Platform` (that edition
includes Vivado), producing a parallel full install rather than an incremental
layer. That is a different build, roughly as long as the Vivado one, and it
does not reuse `vivado-tools:2024.1.2-raw`.

`.xinstall` is still worth preserving -- it is what makes the installed
installer available at all -- but it does not enable an offline Add.

## Installer log location

From `/tmp/installer-log-paths.txt`:

```
=== logs and xinstall trees ===
/root/.Xilinx/xinstall
/root/.Xilinx/xinstall/xinstall-2026-08-18_22-47-33.log
```

The same tree appears on the update media, one file per invocation
(`/root/.Xilinx/xinstall/xinstall-2026-08-18_22-48-02.log`,
`...22-48-09.log`), so the name is `xinstall-<timestamp>.log` and `$HOME` is
what selects the directory.

**Decision:** `container-install.sh` collects logs from `$HOME/.Xilinx/xinstall/` (`/root/.Xilinx/xinstall/xinstall-*.log` when the install runs as root).

## Installer scratch location

From `/tmp/installer-log-paths.txt`:

```
=== directories the installer created ===
/root/.Xilinx
/root/.Xilinx/registry
/root/.Xilinx/xinstall
/tmp/hsperfdata_root

=== does it honour TMPDIR? ===
/probe-tmp
```

`/probe-tmp` is listed by `find` because the probe created it; it is empty. The
second ConfigGen run with `TMPDIR=/probe-tmp` put nothing inside it and went on
writing to `/root/.Xilinx` and `/tmp` as before, so `TMPDIR` is ignored and the
scratch paths must be deleted by name.

**Decision:** the installer's scratch lives at `$HOME/.Xilinx` (`/root/.Xilinx`, containing `registry/` and `xinstall/`) plus `/tmp/hsperfdata_root`, and it does not honour `TMPDIR`. `container-install.sh` sets `SCRATCH_DIR`/`SCRATCH_EXTRA` to exactly these.

---

## Observed at Task 10 (real install, 2026-08-19)

- Vivado reports **v2024.1.2** (`Tool Version Limit: 2024.05`, SW Build 5164865),
  confirming the `-b Update` form recorded above actually applies the update.
- Base install ~4 min, update ~1-2 min, `docker commit` ~25 min. The commit
  dominates: it tars a 37.5 GB container diff.
- Container diff 37.5 GB -> committed image **18 GB**. `docker image inspect
  .Size` reports the compressed size under Docker 29's image store, so the
  image-size ceiling in final.bats is a compressed number and must be recorded
  with the same command it is asserted against.
- Scratch prune verified empty afterwards: none of `/root/.Xilinx`,
  `/tmp/hsperfdata_root`, `/tmp/xinstall` survive into the image.
- `/tools/Xilinx/.xinstall` survives, so `-b Add` (Task 15) can run.

### Two defects the real run exposed

1. **`en_US.UTF-8` must be generated in the base image.**
   `Vivado/2024.1/bin/rdiArgs.sh` line 37 unconditionally exports
   `LC_ALL=en_US.UTF-8`. With only `C`/`C.utf8`/`POSIX` present, `vivado`
   aborts with an unhandled `std::runtime_error` before printing its version,
   and the message never mentions locales.

2. **The build key must not use the base image's `.Id`.**
   BuildKit attaches a provenance attestation to every build, so an identical
   rebuild yields a different `.Id`. Since `install` depends on `base`, the key
   changed on every invocation and the reuse path could never hit -- every
   `make install` restarted a multi-hour reinstall. `.RootFS.Layers` is
   content-addressed and stable; verified by rebuilding the base three times
   and observing the key unchanged.
