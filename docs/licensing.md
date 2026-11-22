# Licensing

Original Steamling work is licensed **GPL-2.0-or-later**. See [LICENSE.md](../LICENSE.md)
for the full license text.

Copyright (C) 2026 David J. Vandenburgh and the Steamling contributors.

Copyright (C) 2026 shuuri-labs and the pocknix-os contributors. Steamling began as a fork of
[Pocknix](https://github.com/shuuri-labs/pocknix-os), and much of this repo is their work.

The support for every handheld besides the Retroid Pocket 6, and many of the patches, come from
[armada](https://github.com/armada-os/armada) (GPL-2.0-or-later, copyright the armada
contributors), renamed to fit Steamling. [PATCHES.md](../PATCHES.md) says which parts.

"Original work" covers everything authored for this project: the build harness (`scripts/`,
`Makefile`, `config/`), device profiles (`devices/`), the rootfs overlay (`overlay/`),
all `steamling-*` packages, PKGBUILDs, and patches written for Steamling. Each package we
author declares `GPL-2.0-or-later` in its PKGBUILD; packages that repackage third-party
content (firmware, the kernel, bootloaders, upstream builds) declare the upstream license.

## Why GPL-2.0-or-later

Much of this repo is derived from GPL-2.0 material and cannot be licensed more permissively:

- The kernel patch series in `kernel/` are derivative works of the Linux kernel
  (GPL-2.0-only), so they are GPL-2.0 regardless of what the top of this repo says.
- Large parts of the patch sets and BSP material are carried from
  [ROCKNIX](https://github.com/ROCKNIX/distribution), whose original software and scripts
  are GPL-2.0.

GPL-2.0-or-later for the rest keeps the whole repo under one coherent, compatible license
instead of a per-directory patchwork.

## Third-party material

Vendored and packaged third-party components keep their upstream licenses. This repo does
not and cannot relicense them. The main ones:

| Component | Where | Upstream license |
|---|---|---|
| Linux kernel + patch series | `kernel/`, `packages/soc/linux-steamling/` | GPL-2.0-only |
| ROCKNIX patches, scripts, BSP material | `kernel/*/patches`, various packages | GPL-2.0 |
| armada device support, patches and settings | `kernel/steamling/`, `devices/*`, various packages | GPL-2.0-or-later |
| OpenABL (fetched, pinned; replaced the ROCKNIX ABL) | `packages/soc/steamling-bootloader` | GPL-3.0-or-later, with a linking exception for its ABL part (Qualcomm's edk2 LinuxLoader underneath; details in its LICENSES.md, installed under /usr/share/licenses) |
| gamescope + patch set | `packages/soc/gamescope` | BSD-2-Clause (the patch set: GPL-2.0; origins in PATCHES.md) |
| Mesa | `packages/soc/mesa` | MIT |
| MangoHud | `packages/shared/mangohud` | MIT |
| FEX-Emu | `packages/soc/fex-emu` | MIT |
| SteamOS Vapor desktop theme (Valve) | `packages/shared/steamos-vapor-theme` | GPL-2.0-or-later, GPL-3.0 (per its metadata) |
| alsa-ucm-conf material | `devices/*` BSPs | BSD-3-Clause |
| Packaged emulators, tools, and libraries | `packages/*` | each project's own license |

PKGBUILDs in `packages/` fetch pinned upstream sources; the resulting binary packages and
OS images contain those projects under their own licenses. Provenance for vendored
binaries is recorded next to them (for example
`packages/soc/steamling-bootloader/README.provenance`) and in [PATCHES.md](../PATCHES.md).

ROCKNIX additionally licenses its distribution branding and artwork under CC BY-NC-SA.
Steamling does not ship ROCKNIX branding; only their GPL-licensed software, scripts, and
patches are used.

From Valve's SteamOS desktop presets only the Vapor theme files are packaged. SteamOS's
wallpapers, avatars, and Steam Deck logo (splash and distributor icon) are not shipped.

## Source availability

Steamling images and packages contain GPL-licensed binaries. For the released ones (the SD
images on SourceForge, the package repo on [Steamling/packages](https://github.com/Steamling/packages)
and the frozen base on [Steamling/base](https://github.com/Steamling/base)), and for any you
build and share yourself, the corresponding source is this repository plus the pinned upstream
sources referenced by each PKGBUILD (exact tags and hashes are in the PKGBUILDs and PATCHES.md).
The base's packages are Arch Linux ARM's own builds, and their sources are Arch Linux ARM's.
