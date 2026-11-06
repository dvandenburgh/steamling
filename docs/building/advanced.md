# Building Steamling: the details

Everything about the build, for when the [step-by-step guide](README.md) isn't enough: how it
works, every option, and building single packages. It works on an ARM machine **or an ordinary
x86_64 Linux PC, including Windows through WSL2**.

- [linux-host.md](linux-host.md) - setting up an x86_64 or aarch64 Linux machine (Ubuntu/Debian,
  Fedora, Arch)
- [wsl.md](wsl.md) - building on Windows with WSL2, flashing the result, and previewing the boot
  splash on your desktop
- [troubleshooting.md](troubleshooting.md) - the errors you are likely to meet, and what each means

## The aarch64 question

Steamling is an **aarch64** (64-bit ARM) operating system, so everything in the image is ARM code.
That does **not** mean you need an ARM computer to build it:

| Step | On an aarch64 host | On an x86_64 host (PC, WSL2) |
|---|---|---|
| Kernel (`make kernel`) | compiled natively | **cross-compiled**: native speed, needs `aarch64-linux-gnu-gcc` |
| Packages and rootfs (`make packages`, `make build`) | run natively in an ARM chroot | the same ARM chroot, run through **qemu-user** (emulation, several times slower) |
| SD image (`make sd-image`) | native | native: just partitioning and copying files |

The emulated steps are the slow part on x86_64. Most of that cost is compiling the big packages
(mesa, gamescope, FEX, the emulators). Your first build compiles all of them; after that, a build
only recompiles the packages whose recipe changed, so it is far quicker.

An aarch64 host (an Arch/Fedora VM on Apple Silicon, an ARM cloud server) needs no emulation at all
and is still the fastest way to build everything from source.

## What a build does

1. **Kernel** - `make kernel` builds the committed kernel (`kernel/<soc>/`) into a boot image.
2. **Packages** - `make build` first builds every Steamling package that is not already in
   `build/localrepo/` at its current version, so after the first build only real changes compile.
3. **Root filesystem** - `make build` then installs the Arch Linux ARM base and the packages into
   `build/rootfs/`, and pre-installs the ARM Steam client so first boot works offline.
4. **Image** - `make sd-image` turns that into a flashable `build/image/<soc>/steamling-<soc>-sd.img`.

`make help` lists every target; `make check` is a preflight that also reports what this host is
missing for an image build.

## Quick start

`./build.sh` builds for the SM8550 handhelds (the Retroid Pocket 6 and the rest of that family).
Add `--device sm8250`, `sm8650` or `sm8750` for the other chips; [Supported devices](../devices.md)
lists which handheld uses which.

```bash
git clone https://github.com/dvandenburgh/steamling && cd steamling
./build.sh                                   # -> build/image/sm8550/steamling-sm8550-sd.img
```

`./build.sh` is the whole build in one command (`make image` is the same thing). Run it as
yourself: it asks `sudo` once, for the steps that need root. On a fresh host it first runs
`make host-setup` to install the build packages (`--no-host-setup` stops and lists them instead).
The kernel and every package skip themselves when already current, so after an
interruption (or a change) the same command redoes only what it must; the rootfs and the image are
always rebuilt.

```bash
./build.sh --ssh                             # SSH on in the image (make image SSH=1)
./build.sh --ssh --wifi MyNet --wifi-psk secret --wifi-country US
./build.sh --no-sd-image                     # stop at the finished rootfs (make rootfs)
./build.sh --update                          # only the changed packages, to update a handheld (make update)
./build.sh --help                            # every option
```

These are the steps it runs, and each is a target of its own:

```bash
make check                                   # host lines must say ok (make host-setup fixes most)
sudo make kernel
make pending                                 # what `make build` would still compile
sudo make build
sudo make sd-image                           # -> build/image/sm8550/steamling-sm8550-sd.img
```

Flash the image with balenaEtcher, Rufus, or `dd`, then follow the
[install guide](../install.md).

Device firmware is a package like any other (`steamling-firmware-sm8550`, fetched at a pinned
commit and checked by sha256), so no step puts it in
place by hand. `make sync` only refreshes ROCKNIX
reference material in `vendor/`, which no build reads.

If you keep a ROCKNIX checkout of your own at `../distribution` (or point `DISTRIBUTION_DIR` at
one), `make sync` reads it instead of the pinned commit. With `STEAMLING_SYNC_SCOPE=all` it also
refreshes the committed kernel inputs in `kernel/<soc>/` from it: that is how the kernel moves to a
newer ROCKNIX.

### Before `make build`: read `make pending`

`make pending` lists every package `make build` would compile: on a first build that is all of
them, after that only the ones whose recipe changed since you last built them, plus the kernel
package (`linux-steamling-<soc>`, which is just repackaged from your `make kernel` output). If it
lists something big like `mesa`, `gamescope` or `dolphin-emu` you didn't expect, a `git pull`
moved that package's version. Compiling it under qemu takes hours, so plan for it.

### Useful build options

Give them to `./build.sh` as flags, or set the variable on the `make` command line or in your
environment (for example `make image SSH=1`, `export SSH=1` to make it the default, or
`sudo SSH=1 make sd-image` for a single step). The on/off switches take `on`/`off`, `1`/`0`,
`yes`/`no` or `true`/`false`.

| `./build.sh` flag | Variable | Effect |
|---|---|---|
| `--ssh` / `--no-ssh` | `SSH=1` (or `SD_SSH=on`) | SSH in the image (the root and `deck` password is `root` unless you set one - test images only) |
| `--password PW` | `SD_ROOT_PASSWORD=PW` | the root and `deck` password baked into the image |
| `--wifi SSID --wifi-psk PSK --wifi-country US` | `SD_WIFI_SSID= SD_WIFI_PSK= SD_WIFI_COUNTRY=` | pre-configure Wi-Fi in the image |
| `--emulation` | `STEAMLING_EMULATION=1` | bake the emulation layer (ES-DE and emulators) into the image |
| (none) | `STEAMLING_IMAGE_PKG_CACHE=1` | keep a copy of every installed package in the image's `/var/cache/pacman/pkg` (several GB; handy on test devices for rolling a package back offline) |
| (none) | `STEAMLING_NOEXTRACT=` | keep package documentation in the image (left out by default; the value is pacman's `NoExtract` list) |
| (none) | `STEAMLING_FIRMWARE_SKIP=` | keep every Qualcomm platform's firmware in the image (by default the folders for platforms no Steamling board uses, about 430 MB, are left out, now and on updates) |
| `--jobs N` | `JOBS=N` | parallel jobs for the kernel build (default: all cores) |
| (none) | `STEAMLING_CCACHE=off` | compile packages from scratch instead of reusing the ccache in `build/cache/ccache-pkg` (`STEAMLING_CCACHE_SIZE` sets its limit, 20G by default) |
| `--no-sd-image` | `SD_IMAGE=off` | stop at the finished rootfs (`make rootfs`) |
| `--update` | `STEAMLING_UPDATE=1` | build only the kernel and the packages that changed, with no rootfs or SD image (`make update`): what [updating over the network](../updating.md#updating-from-your-own-build-without-reflashing) needs |
| `--no-host-setup` | `STEAMLING_HOST_SETUP=off` | stop when host packages are missing instead of installing them |
| `--no-status-bar` | `STEAMLING_STATUS_BAR=off` | plain output, without the status line at the bottom |
| (none) | `STEAMLING_BASE_SNAPSHOT=live` | build straight from Arch Linux ARM's own repos and latest tarball instead of the frozen base: nothing to host or upload, but every build gets whatever ALARM has that day (put it in `config/local.conf` to keep it) | <!-- docs-check: allow -->
| `--build-base` | (none) | cut your own frozen base first, upload it, then build against it ([own-base.md](own-base.md)); without it, builds use the base already pinned |

### Watching a build

While `./build.sh` runs, the bottom row of the terminal is a status bar: the step it is on, what
that step is doing (which package is compiling, for example), the time so far, and an estimate of
the time left with the clock time it should finish. The terminal's title shows the same in short,
so you can see it from another tab. From any other shell in the checkout:

```bash
make status                                  # every step: its time, or its estimate
make watch                                   # the same, redrawn every 2 s until the build ends
```

The estimate comes from how long each step, and each package, took on this machine the last time
(kept in `build/progress/`), and from the same checks the steps use to skip work: a current kernel
or package counts as seconds, not hours. The first build on a machine has nothing to go on, so its
estimate is a rough guess and says so; from the second build on it is close.

## Building just a package

You do not need a full image to test a change. Build the package, copy it over, and install it on a
running device:

```bash
sudo make packages PKG="steamling-branding"                  # -> build/localrepo/<soc|shared>/
scp build/localrepo/shared/steamling-branding-*.pkg.tar.* deck@steamling:/tmp/
ssh -t deck@steamling 'sudo pacman -U /tmp/steamling-branding-*.pkg.tar.*'
```

(Log in as `deck`: root can't log in over SSH.) A package whose build needs packages Steamling
builds itself (for example `steamling-steam` needs `gamescope`) finds them in `build/localrepo/`,
so build those first; after one full build they are all there. To send everything you rebuilt in
one go instead of package by package, see [Updating Steamling](../updating.md). See
[CONTRIBUTING.md](../../CONTRIBUTING.md) for how to test and submit a change.

## Space and time

Plan on roughly **100 GB free** for a full build (build chroot, rootfs, kernel tree with debug info,
caches, and the image). Rough times on a recent 8-core x86_64 PC: kernel 20-40 minutes the first
time, `make build` one to three hours under qemu once every package is compiled (the first time,
compiling them all adds many hours on x86_64), `make sd-image` 10-20 minutes. An aarch64 host is faster for the package and rootfs steps.
`make kernel` does nothing when `kernel/<soc>/` has not changed since its last build, and with
ccache installed a small kernel change rebuilds in minutes. Packages use their own ccache inside
the build chroot, so after the first build a version bump or a small patch only recompiles the files
that changed. It needs up to 20 GB in `build/cache/ccache-pkg`. ccache has to be in the package
base the build uses: the current frozen base doesn't carry it, so for now the build says so and
compiles without it. A base snapshot taken after a live-base build includes it.

## Upstream mirrors (optional)

`make mirrors` keeps bare clones of the upstreams this tree patches or tracks (mesa, gamescope,
the kernel, ROCKNIX and the rest of `config/mirrors.list`) under `build/mirrors/`, and fetches
them again on every run. No build step reads them: they are for rebasing patches and seeing what
upstream changed. On a Windows checkout run `scripts/mirrors.ps1` instead.
