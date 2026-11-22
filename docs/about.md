# About Steamling

<p align="center">
  <img src="images/steamling-logo.svg" alt="Steamling logo" width="220">
</p>

## Why it exists

I wanted my handheld to work the way a Steam Deck does: turn it on, Steam is there, games just
run. ARM handhelds have amazing hardware, but getting a proper SteamOS-style experience on them
has meant a lot of tinkering. Steamling is me trying to close that gap. It's a gaming system
first, and a full Arch Linux machine underneath for anyone who wants to dig in.

The name is a small joke: a steamling is a baby dragon that's still learning to breathe fire, so
for now it just puffs steam. That's the little guy in the logo, peeking over the top of a
handheld.

## Thank you

Steamling wouldn't exist without the people below. A lot of what's in this repo is their work,
carried over with their licenses and credits intact. If you like Steamling, please go and give
these projects some love too.

### The projects it's built on

- **[Pocknix](https://github.com/shuuri-labs/pocknix-os)** by shuuri-labs. Steamling began as a
  fork of Pocknix, and its build system, packaging, session setup and a huge amount of careful
  device work all come from there, and Steamling built from the frozen Arch Linux ARM base that
  Pocknix hosts until it had its own. Thank you for doing the hard groundwork and sharing it so
  openly.
- **[ROCKNIX](https://github.com/ROCKNIX/distribution)** and its contributors. The kernel, the
  bootloader (ABL) that lets these handhelds boot Linux at all, the Snapdragon device support,
  and the panel refresh calibration all come from ROCKNIX. None of this runs without them.
- **[armada](https://github.com/armada-os/armada)**, for the HDR and color work, the suspend
  fixes, the gamescope and MangoHud patches, the RP6 firmware and a long list of kernel fixes.
  armada is also where Steamling's support for every handheld besides the RP6 comes from: their
  combined kernel, device trees, controller and audio setups made those ports possible.
- **[PortareOS](https://github.com/portare-ch/portareos)**, whose Retroid Pocket Nova work brought
  a handful of SM8550 kernel fixes, with the measurements behind them.
- **[thorch](https://github.com/thorch-os/thorch)**, for the power and suspend work shared
  with armada.
- **[Arch Linux ARM](https://archlinuxarm.org/)**, the base everything sits on.
- **Valve**, for SteamOS, the ARM Steam client, [gamescope](https://github.com/ValveSoftware/gamescope)
  and [steamos-manager](https://gitlab.steamos.cloud/holo/steamos-manager), and for showing
  what a handheld PC should feel like.
- **[FEX-Emu](https://github.com/FEX-Emu/FEX)**, which runs x86 games and Steam's Windows tools
  on ARM. It's close to magic.
- **[Mesa](https://www.mesa3d.org/)** and the Turnip/freedreno developers, for the open Adreno
  graphics drivers.
- **[KDE](https://kde.org/)** and **[Plasma Mobile](https://plasma-mobile.org/)**, for desktop
  mode.
- **[CachyOS](https://cachyos.org/)**, for system tuning ideas and
  [Proton-CachyOS](https://github.com/CachyOS/proton-cachyos), and
  **[GloriousEggroll](https://github.com/GloriousEggroll/proton-ge-custom)** for Proton-GE.
- **[ChimeraOS](https://chimeraos.org/)**, for the gamescope session setup that the game mode
  session borrows from.
- **[sched-ext](https://github.com/sched-ext/scx)**, for the LAVD CPU scheduler.
- **[Decky Loader](https://github.com/SteamDeckHomebrew/decky-loader)**, which Governor
  runs on, and **[InputPlumber](https://github.com/ShadowBlip/InputPlumber)** by ShadowBlip for
  controller handling.
- **[MangoHud](https://github.com/flightlessmango/MangoHud)**, for the performance overlay.
- **GPcal** by Kdog (Cyril Delétré), whose stick calibration math lives on in Governor.
- **[ES-DE](https://es-de.org/)**, **[RetroArch and libretro](https://www.libretro.com/)**,
  christianhaitian's ArkOS cores, and every emulator project packaged here: Dolphin, Cemu,
  Azahar, Flycast, Mupen64Plus-Next, SwanStation, ARMSX2, RPCS3, Vita3K and xemu.
- **Bricolage Grotesque**, the open font (SIL OFL) used for the Steamling wordmark.

### The people in the patch headers

A lot of the fixes in `kernel/` and `packages/` were written by individual developers, and their
names stay on every patch and script. To name some of them: Neil Armstrong, Konrad Dybcio, Philippe Simons,
Teguh Sobirin, tiopex, spycat88, John Williams, virtudude, jaewun, JS Deck, enjihn,
sunshineinabox, Diogo Trindade, Luke Johnson, Changwoo Min, Jacob Cook, Ashketchup and many more.
Thank you all. [PATCHES.md](../PATCHES.md) records where each patch came from.

If you see your work in here and I've credited it wrong or missed you, please open an issue and
I'll fix it.

## The developer

I'm David J. Vandenburgh. During the day I work in IT and cloud operations, mostly Azure,
Kubernetes and a lot of PowerShell. At home I'm the guy who builds his own kernels and has run
Arch on just about everything.

Before this, I spent years in the Android custom ROM scene as **Seraph08** on XDA Developers.
Most of my work there was on OnePlus phones: the OnePlus 2 and OnePlus X, the 3 and 3T, and the 5
and 5T and later. I was an official member of the BrokenROM team (BrokenOS), building and
maintaining ROMs for those devices. That's where I learned most of what I know about kernels,
device trees, and getting an OS to boot on hardware that was never meant to run it, which is
pretty much what Steamling is.

Handhelds feel a lot like those early OnePlus days: great hardware, a community that loves to
tinker, and plenty of room to make things better. Steamling is my way of getting back into it.

## Get involved

Bug reports, fixes and emulator configs are all welcome. See [CONTRIBUTING.md](../CONTRIBUTING.md),
or open an issue on [GitHub](https://github.com/dvandenburgh/steamling/issues).
