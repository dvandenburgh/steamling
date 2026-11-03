# Steamling docs

User guides for Steamling. New here? Start with the [project README](../README.md).

- [devices.md](devices.md) - every supported handheld, what "untested port" means, and how to
  help test one
- [install.md](install.md) - flashing the SD card, installing the bootloader (OpenABL), and first
  boot
- [updating.md](updating.md) - getting a newer build onto the handheld, by reflashing or over your
  home network
- [known-issues.md](known-issues.md) - what does not work, or not well, yet
- [governor.md](governor.md) - the in-game control panel: per-game tweaks, fan/CPU
  modes, adding non-Steam games, file sharing over the network or USB, SSH, SD card formatting,
  controller calibration, stick lights, display calibration, and system updates
- [emulation-setup.md](emulation-setup.md) - where to put ROMs, BIOS, and firmware, how to launch
  games, and how to tweak emulator settings
- [heroic.md](heroic.md) - Epic, GOG and Amazon games with the Heroic Games Launcher
- [waydroid.md](waydroid.md) - running Android apps: setup, installing apps, and app shortcuts
- [desktop-controls.md](desktop-controls.md) - using the controller in desktop mode: moving
  between icons, the pointer, and typing on the on-screen keyboard
- [install-to-internal.md](install-to-internal.md) - moving Steamling from the SD card onto the
  device's internal storage, the bootloader menu that picks what boots, uninstalling, and
  restoring the factory bootloader
- [snapshots.md](snapshots.md) - automatic pre-update snapshots, one-button rollback, and
  manual recovery when an update goes wrong
- [benchmarking.md](benchmarking.md) - measuring boot time, battery drain asleep, clocks and
  temperatures, controller reports and frame times before and after a change
- [licensing.md](licensing.md) - the project license and the third-party components it ships
- [about.md](about.md) - where Steamling came from, the projects and people it's built on, and
  who makes it

## For developers

See [CONTRIBUTING.md](../CONTRIBUTING.md) for how to build, test, and submit a change.
[building/](building/README.md) walks you through a build step by step, on Linux or on Windows
with WSL2; [building/advanced.md](building/advanced.md) has every option, and
[building/own-base.md](building/own-base.md) covers building from live Arch Linux ARM and hosting
your own frozen base.
