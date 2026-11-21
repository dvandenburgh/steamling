# devices/ - the device-abstraction boundary

Everything device-specific lives here (or in `kernel/<soc>/`). Shared code never
hardcodes a device fact: the **build** reads `devices/<name>/profile.conf` (sourced by
`scripts/lib.sh` right after `config/steamling.conf`), and the **running OS** reads
`/usr/lib/steamling/device.conf`, shipped by the family's BSP package.

`DEVICE` names an **image target**, a SoC family, and each family image serves every board on
its SoC (`make build DEVICE=sm8550` is the default). The BSP
(`steamling-bsp-<soc>`) ships per-board facts in `/usr/lib/steamling/boards/<board>.conf`,
each sourcing the family-wide `boards/family.conf` first, and
`/usr/lib/steamling/device.conf` is a sourced **dispatcher** that picks one at source time
by `/proc/device-tree/model`. `scripts/render-bsp.sh` renders it at package time from the
BSP's `boards/models` table (`<board> <dt model>` rows). InputPlumber configs are gated with
`matches:` on the devicetree model. Since consumers *source* `device.conf`, the dispatcher
is invisible to them; `/etc/steamling/device.conf` still overrides.

The families. The Retroid Pocket 6 is the reference board: it is the only one tested so far, and
it boots Steamling from the SD card into game mode.
Every other board is an **untested port** brought over from
[armada](https://github.com/armada-os/armada): it builds, and armada boots it, but nobody has run
Steamling on it yet.

* **sm8550** (qcom-abl): Retroid Pocket 6 (+TOP-DPAD), Retroid Pocket Nova, AYN Odin 2 / Mini /
  Portal, AYN Thor, AYANEO Pocket ACE / DMG / DS / EVO / S 1K / S 2K. Kernel: `kernel/sm8550/`
  (ROCKNIX-synced). The RP6 device tree includes the shared AYN SM8550 dtsi but names its sound
  card `SM8550-RetroidPocket-I2S`, as Retroid does, for Retroid's UCM with the built-in mics; it
  loads the RP6's own DSP and amp firmware and the Odin 2 audio topology. The Nova includes the
  RP6 tree.
* **sm8250** (qcom-abl): Retroid Pocket 5, Retroid Pocket Flip 2, Retroid Pocket Mini / Mini V2,
  AYN Thor Lite, MANGMI Air Y Pro, MANGMI Pocket Max, AYANEO Pocket MICRO 2; the RP5 and Flip 2
  also as Visionox-panel revisions (their own dtb and board conf). Kernel: `kernel/steamling/`.
* **sm8650** (qcom-abl): AYANEO Pocket S2, KONKR Pocket FIT. Kernel: `kernel/steamling/`.
* **sm8750** (qcom-abl): AYN Odin 3, KONKR Pocket FIT Elite. Kernel: `kernel/steamling/`.

The first board a bullet names is the family's fallback: it must be the first `boards/models`
row, which an unknown or absent model gets (`make check` pins the two together).

Adding a **board to a family**: a `boards/<board>.conf` (only what differs from
`boards/family.conf`) + its `boards/models` row(s) + (if its controller differs) an
inputplumber yaml/map with the board's dt-model `matches:` + a `[[device]]` entry in the
BSP's `root/usr/share/steamos-manager/devices/steamling-family.toml`, ahead of the SoC entry.
Bump the BSP pkgrel. No new packages, no new image.

## Where a new file goes

* Data about one chip (profile, tuning, freqs, boards) goes in `devices/<soc>/`.
* A chip's own `arch=any` packages (its BSP, its device meta) go in `devices/<soc>/packages/`.
* A recipe built per chip goes in `packages/soc/`, gated by its `socs` file. The goal is
  one recipe for every chip: `packages/soc/linux-steamling/` builds every chip's kernel
  package from its `kernel/<soc>/kernel.conf`, and `packages/soc/steamling-bootloader/` every
  chip's OpenABL kit.
* `packages/shared/` only if the bytes are identical for every chip.

## What a family target must provide

```
devices/<soc>/
  profile.conf                    # build-time facts that differ per family (see devices/sm8550):
                                  #   SOC (selects kernel/<soc>/ + vendor/rocknix-<soc>/),
                                  #   BOOTLOADER (qcom-abl),
                                  #   KERNEL_CMDLINE_ROOT / KERNEL_CMDLINE_EXTRA (ONE cmdline
                                  #   for the family), DEVICE_PRETTY.
                                  #   Defaults a profile may override: config/steamling.conf
                                  #   (DEVICE_HOSTNAME, SD_FAT_LABEL / SD_BOOT_PARTNAME /
                                  #   ROOT_LABEL, set before the profile: override with X=value)
                                  #   and scripts/lib.sh's profile_defaults (KERNEL_CMDLINE,
                                  #   DEVICE_BSP_PKG / DEVICE_META_PKG / KERNEL_PKG from SOC)
  freqs.txt                       # (with power-profiles.d tables) available cpufreq/devfreq
                                  #   frequencies the tables are checked against
  tuning.conf                     # userspace compiler tuning for the chip's per-SoC
                                  #   builds: STEAMLING_TUNE_CFLAGS (ROCKNIX's TARGET_CPU/FLAGS
                                  #   composed as -march/-mtune), STEAMLING_FEX_TUNE_CPU (per
                                  #   their fex package.mk mapping)
  packages/
    steamling-bsp-<soc>/            # the family BSP: boards/ (family.conf, one conf per board,
                                  #   models = the table device.conf is rendered from;
                                  #   STEAMLING_BOOT_STYLE / BOOT_FAT_LABEL / ROOT_LABEL are
                                  #   rendered into family.conf from the profile) +
                                  #   root/, the install tree copied as is (git carries the
                                  #   exec bits and symlinks; make check wants 755 exactly on
                                  #   files with a shebang): input maps
                                  #   (dt-model gated), udev quirks, audio UCM, SoC
                                  #   suspend config, steamos-manager's device match
                                  #   (usr/share/steamos-manager/devices/steamling-family.toml:
                                  #   the boards, then a qcom,<soc> catch-all), steamling-perfd's
                                  #   underclock tables (usr/share/steamling/power-profiles.d/
                                  #   family.conf, checked against freqs.txt).
                                  #   No kernel-cmdline: the build renders it from the profile.
                                  #   MUST: depends=(steamling-bsp-common)
                                  #   provides/conflicts=(steamling-bsp)   <- wrong-device guard
    steamling-device-<soc>/         # metapackage: depends on the BSP + kernel + bootloader
                                  #   + its protons.
                                  #   Nothing every family needs: that goes on steamling-core.
                                  #   MUST provides/conflicts=(steamling-device).
    steamling-firmware-<soc>/       # (optional) vendor firmware linux-firmware lacks or gets wrong,
                                  #   fetched by pinned commit + sha256 (never from vendor/),
                                  #   installed under /usr/lib/firmware/updates/; only boards
                                  #   in the BSP's boards/models. The BSP depends= on it.
```

If the family brings a **new SoC**, also create `kernel/<soc>/` (`kernel.conf` with the
source pins, `KERNEL_PKGREL` (1 for a new chip) + `config/ patches/ dts/` -
populated by `make sync` against the ROCKNIX device dir named in `ROCKNIX_SOC`); the kernel
package needs no recipe of its own (`packages/soc/linux-steamling/` packages `make kernel` output,
plus `mkbootimg`; the /flash deploy is bsp-common's and needs nothing per SoC), and
an OpenABL release with a `<SOC>/` folder for `packages/soc/steamling-bootloader/` to copy to the SD
boot FAT. Each SoC gets its own pacman repo tree
(`build/localrepo/<soc>`): the tuned packages
(mesa, gamescope, fex-emu) share pkgnames across SoCs with different
binaries, so the repos must not mix. They build for every SoC already (`socs` = `all`);
a SoC-specific kernel config or a local patch delta goes in `kernel/<soc>/` (see
kernel/README.md). `make check` validates every family: required files, family and board keys,
the models table against boards/ and the dts model lines, the consumers' fallbacks, the rendered device.conf and family.conf, and that
the cmdline has no committed copy outside the profile. The BSP PKGBUILD installs what the
build stages into its `./staged` (device.conf, family.conf and kernel-cmdline):
copy an existing family's `package()`.

## Boot styles (`BOOTLOADER` in profile.conf)

On the device the style is `STEAMLING_BOOT_STYLE`, rendered into the BSP's family.conf from
`BOOTLOADER`; bsp-common's `steamling-boot-deploy` runs that style's /flash deploy for every
kernel update, rollback and cmdline change. Kernel packages ship no deploy scripts or hooks.

* `qcom-abl` (sm8550): OpenABL (the ROCKNIX ABL before it) boots an Android boot image (`/KERNEL`,
  mkbootimg, cmdline baked in, all dtbs appended - ABL picks by board id). The BSP
  ships `/usr/lib/steamling/kernel-cmdline`, which build-packages.sh renders from the profile's
  `KERNEL_CMDLINE` into its `./staged`; bsp-common's kernel hook rebuilds /flash/KERNEL on device.
  The SD boot FAT also carries `openabl/` (steamling-bootloader-<soc>; `rocknix_abl/` before
  October 2026): the first-install kit for flashing that ABL from rooted stock Android - inert at boot,
  Steamling never flashes it itself.

## The runtime contract (`/usr/lib/steamling/device.conf` -> `boards/<board>.conf`)

Sourced at launch by shared scripts (`steamling-steam`, the desktop session, bsp-common's
`cores.sh`, the emulation launchers, the install and rollback tools; the table names each);
`/etc/steamling/device.conf` is the admin override (sourced after, wins). Every key a script
that sources device.conf (or `cores.sh`) reads has a row, and `make check` fails on one that
does not. Absent = `required` means every board resolves it (`make check` fails a board that
leaves it unset); otherwise it says what a board without the key gets. Keys:

| Key | Used by | Absent | Meaning |
|---|---|---|---|
| `STEAMLING_DEVICE` / `STEAMLING_SOC` | anything | required | identity; steamling-steam also passes `STEAMLING_DEVICE` to gamescope as GAMESCOPE_INTERNAL_DEVICE_ID, which the BSP's panel profiles match on |
| `STEAMLING_PANEL_W` / `STEAMLING_PANEL_H` / `STEAMLING_PANEL_REFRESH` | steamling-steam, steamling-roms-init (refresh also: es-retroarch) | required | gamescope -W/-H/-r |
| `STEAMLING_PANEL_ORIENT` | steamling-steam, steamling-roms-init | required | gamescope --force-orientation |
| `STEAMLING_PANEL_MM` | steamling-steam | required | GAMESCOPE_FAKE_OUTPUT_MM (gamepadui DPI; deliberately faked on small panels) |
| `STEAMLING_DESKTOP_ROTATE` / `STEAMLING_DESKTOP_SCALE` | steamling-desktop-rotate | required | kscreen-doctor rotation/scale (seeded once per user; env re-forces) |
| `STEAMLING_BOARD_UNKNOWN` | steamling-desktop-rotate | board known (only the fallback branch sets it) | set by the device.conf fallback branch: board not in the list, do not force guessed values |
| `STEAMLING_PANEL_OUTPUT` | steamling-steam, steamling-desktop-rotate | single panel, first DSI | DRM connector of the main panel (`DSI-2`); gamescope `--prefer-output`, the desktop seed's output |
| `STEAMLING_PANEL_BACKLIGHT` | steamling-board-env (90-steamling-backlight.rules), steamos-priv-write | single panel: Steam writes the backlight directly | two-screen boards only: the main panel's `/sys/class/backlight` name. Every backlight stays read-only for the session, so Steam's slider goes through steamos-priv-write, which writes it here instead of the first backlight Steam finds (often the second screen's) |
| `STEAMLING_PANEL_ROTATE_SHADER` | steamling-steam | rotation autodetected | `1` = gamescope `--force-composition-rotation`: required for a panel past the DPU rotator's 1088-line cap, which otherwise scans out black |
| `STEAMLING_GAMEPAD_QUIRK` | steamling-gamepad-quirk | none | controller MCU mode switch before InputPlumber starts: `ayaneo-xbox` (AYANEO Pocket MCUs as a fake Xbox 360 pad) or `ayaneo-default` (the MCU's own mode, AYANEO Pocket DS/S2 and KONKR) |
| `STEAMLING_PANEL_HDR_NITS` | steamling-steam | no HDR | HDR panel's peak in nits: gamescope `--hdr-itm-target-nits` plus GAMESCOPE_EXPOSE_CLIENT_SAMPLEABLE_FORMATS=1 and, for the Steam client, STEAM_GAMESCOPE_HDR_SUPPORTED=1 (its HDR switch). Set only with a gamescope panel profile (`/usr/share/gamescope/scripts/10-steamling/displays/`, all of them shipped by steamling-bsp-common) matching the board's `STEAMLING_DEVICE` with the same peak as its `max_content_light_level`: the profile is what tells gamescope the EDID-less panel can do HDR. Absent or 0 = SDR |
| `STEAMLING_PAD_LETTERS` | steamling-roms-init | Xbox lettering | `nintendo`: the face buttons are lettered A right, B bottom, X top, Y left, so seeds that put an action on a letter follow the print (ES-DE confirms with A and shows Switch prompts). Set only where an owner has confirmed it; a unit lettered otherwise overrides it in `/etc/steamling/device.conf` |
| `STEAMLING_BIG_CORES` | via cores.sh: steamling-steam-env (-> steamling-game-launch), steamling-rt-ladder, emulator launchers | required | cores games and emulators are pinned to; the cores left out are the small cores irq work goes to (on a SoC with no little cluster, leave two mids out) |
| `STEAMLING_BOOT_STYLE` | steamling-install-internal, steamling-boot-deploy (the kernel hook, steamling-rollback, steamling-cmdline-sync) | required | qcom-abl (rendered from the profile's `BOOTLOADER`): selects the /flash kernel deploy (`steamling-build-bootimg`) |
| `STEAMLING_INTERNAL_DISK` | steamling-install/uninstall-internal, installer-gui, steamling-tools, steamling-rollback, steamling-internal-boot-rename | required | internal disk |
| `STEAMLING_BOOT_GPT_NAME` / `STEAMLING_BOOT_FAT_LABEL`, `STEAMLING_ROOT_LABEL` | steamling-install/uninstall-internal, steamling-tools (root label), steamling-rollback, steamling-internal-boot-rename (root label) | required | internal-install boot contract (the two labels are rendered from `SD_FAT_LABEL` / `ROOT_LABEL`, config/steamling.conf defaults a profile may override) |

Env overrides read by the same scripts, never set in device.conf: `STEAMLING_ROTATE` /
`STEAMLING_SCALE` / `STEAMLING_OUTPUT` (steamling-desktop-rotate re-forces the desktop seed with them).

Picking the display values for a new board:

* `STEAMLING_PANEL_W/H` are the panel's NATIVE frame. `STEAMLING_PANEL_ORIENT` is `left`/`right`
  for a portrait panel mounted landscape (the consumers transpose) and `normal` for a
  landscape-native panel (no DT `rotation`): W/H pass through untransposed and
  `STEAMLING_DESKTOP_ROTATE=none`.
* `STEAMLING_PANEL_MM` stays `177x100` unless a tester says otherwise. It is a fake that sets
  gamepadui's dpi (`W * 25.4 / 177`), field-validated on 1920- and 1280-wide panels; deviate
  only if the UI crops (dpi too high for the width) or reads tiny.
* `STEAMLING_DESKTOP_SCALE` = the largest 0.25 step that keeps the logical short side >= 480
  (the Plasma Mobile shell needs the height): 1080-line panels -> 2.5, 960-line -> 2.0.

Every consumer also falls back to the RP6 values when a required key (or the whole file) is
absent, so a missing/partial device.conf degrades to known-good behavior instead of breaking.
`make check` holds each consumer's `${STEAMLING_<key>:-<value>}` to that rule: a required key's
fallback is the RP6 value, an optional key's is 0 or empty, and `scripts/fallbacks.allow` lists
the exceptions with a reason.

## Bring-up checklist for a new board

1. Confirm the board's dtb is in `kernel/<soc>/dts` (re-`make sync` if ROCKNIX added it)
   and note the DTS `model =` string - it keys everything at runtime (`make check` fails a
   `boards/models` row that no `model = "...";` under `kernel/<soc>/dts` declares).
2. `boards/<board>.conf` in the family BSP (panel geometry/orientation from the DTS; keys
   every board shares, like `STEAMLING_BIG_CORES`, live in `boards/family.conf`); display
   values per the rule above + a `boards/models` row per DT model string.
3. InputPlumber: extend the family yaml's `matches:` if the board shares the family
   controller, or add a new model-gated yaml + capability map if it differs.
4. UCM if the sound card name differs; udev quirks as needed.
5. `make check` (board keys, models table); bump pkgrels; `make build DEVICE=<soc>`.
   No shared file should need editing; if one does, the boundary has a hole: fix the
   boundary, not the device.
