# Build troubleshooting

The errors a build host is most likely to hit, by the message you see. Start with `make check`:
its host lines catch most of these before a build starts.

## Host setup

**`Package 'qemu-user-static' has no installation candidate`**

Ubuntu 26.04 and later only keep `qemu-user-static` as a placeholder name, so apt refuses it and
installs nothing else from the same command either (which is why `make check` then also reports
the cross compiler missing). Update this checkout and run `make host-setup` again: it installs
`qemu-user-binfmt` there instead. By hand, use the apt line in
[linux-host.md](linux-host.md#1-host-packages) with `qemu-user-binfmt` in place of
`qemu-user-static`.

**`sudo: effective uid is not 0, is /usr/bin/sudo on a file system with the 'nosuid' option set ...`**\
**`error binfmt qemu-aarch64 has flags 'POF', without C: sudo in the build chroot cannot gain root.`**

The qemu-aarch64 binfmt registration lacks the `C` flag, so `makepkg`'s `sudo` cannot become root
inside the ARM build chroot. Debian and Ubuntu (WSL included) register it that way. Fix:
[The qemu binfmt C flag](linux-host.md#3-the-qemu-binfmt-c-flag-x86_64-hosts).

**`error no enabled aarch64 binfmt handler on x86_64`**\
**`error cross-building on x86_64 needs /usr/bin/qemu-aarch64-static, the qemu the aarch64 binfmt handler runs`**

qemu-user is not installed, or not registered with the kernel. Install the qemu package for your
distro from [linux-host.md](linux-host.md#1-host-packages) (on Arch, `qemu-user-static-binfmt` does
the registration; on Ubuntu 26.04 and later, `qemu-user-binfmt`). The registration is done by `systemd-binfmt` at boot, so on WSL make sure
[systemd is running](wsl.md#1-install-wsl-and-ubuntu).

**`error cross-building on x86_64: need aarch64-linux-gnu-gcc (or set CROSS_COMPILE)`**

`make kernel` needs the aarch64 cross compiler on an x86_64 host. Install it from
[linux-host.md](linux-host.md#1-host-packages); a toolchain with another prefix works with
`CROSS_COMPILE=<prefix>-`.

**`error missing required tool: pahole`** (or any other tool)

Install the host packages for your distro. The less obvious ones: `pahole` comes from `dwarves`
(`pahole` on Arch), `sgdisk` from `gdisk` (`gptfdisk` on Arch), and `bsdtar` from
`libarchive-tools` on Debian/Ubuntu.

**`checkout filesystem v9fs: build from a Linux filesystem instead`** (in `make check`; the name varies)

The checkout is on a Windows drive (`/mnt/c/...`) or another filesystem without Unix permissions.
Clone again under your Linux home (`~/steamling`); see [wsl.md](wsl.md#3-clone-inside-linux-not-on-c).

**`btrfs (make sd-image) MISSING in this kernel`** (in `make check`)

`make sd-image` formats the root partition as btrfs. Try `sudo modprobe btrfs`; on WSL, run
`wsl --update` and `wsl --shutdown` in PowerShell.

**`gcc: fatal error: Killed signal terminated program cc1`**

The host ran out of memory. Close other programs, add swap, or lower the kernel build's parallelism
(`sudo JOBS=4 make kernel`). On WSL, raise the memory and swap limits in
[`.wslconfig`](wsl.md#2-give-wsl-enough-memory-and-disk).

## Firmware and kernel

**`error patch failed to apply: .../kernel/<soc>/patches/...`**

`make kernel` applies every file under `kernel/<soc>/patches/`, tracked by git or not. If the error
lists changes git does not know about, they are usually left from an older `make sync` that pulled
ROCKNIX's newer patch stack into `kernel/`. Restore the committed tree and build again:

```bash
git checkout -- kernel/sm8550 && git clean -fd kernel/sm8550
make image
```

**`error ROCKNIX device dir not found: ...`**

Your own ROCKNIX checkout (`../distribution` or `DISTRIBUTION_DIR`) lacks this SoC's device dir.
Add `projects/ROCKNIX/devices/<SOC>` to its sparse checkout, or move the checkout aside so
`make sync` fetches the pinned commit into `vendor/distribution` itself.

**`error could not fetch https://github.com/ROCKNIX/... at ...`**

`make sync` cannot reach GitHub, or a proxy is in the way. `git` must be able to fetch from
`github.com`; check with `git ls-remote https://github.com/ROCKNIX/distribution`. No build step
needs `make sync`, so an image still builds without it.

**`git status` shows many changes under `kernel/` after `make sync`**

`make sync` ran with `STEAMLING_SYNC_SCOPE=all` and moved the committed kernel to whatever the ROCKNIX
checkout holds. Put it back with `git checkout -- kernel/` (plus `git clean -fd kernel/` for files it
added), then run plain `make sync`.

**`error linux-steamling-<soc> not in [steamling] — run 'make kernel' first`**

`make build` packages the kernel from `make kernel`'s output. Run `sudo make kernel`, then
`sudo make build` again.

## Packages

**`make pending` lists `mesa`, `gamescope`, an emulator or another big package**

`make build` will compile it, and under qemu that can take hours. On a first build every package is
listed. After that, it means the package's version changed: a `git pull` brought a newer recipe, or
you changed it yourself. The compile is expected; it only happens once per version.

**`error still mounted under .../build/pkgbuild-root-<soc>, not wiping it`**

An earlier build was interrupted and left the package chroot's mounts in place, including a bind
mount of the host's `/dev`. Reboot to clear them (on WSL, `wsl --shutdown` in PowerShell), check
that `findmnt | grep pkgbuild-root` prints nothing, then run the build again. Never delete anything
under `build/` while they are there: `rm -rf` follows the `/dev` bind mount and removes the host's
device nodes. `make clean` refuses in that state for the same reason.

**`error chroot base upgrade failed — refusing to build against a stale base`**

The package build chroot could not reach the Arch Linux ARM mirrors. Re-run when the network is
back.

**`make packages` prints the package list, then `make: *** [Makefile:...: packages] Error 2`**

Older checkouts failed this way when `build/localrepo/<soc>/` or `shared/` was empty, even though
every package built. Update your checkout; the packages that were built are fine.

## SD image

**`error loop partitions /dev/loopNp1/p2 did not appear`**

The kernel did not create partition devices for the image's loop device. This happens in containers
(Docker, Podman, systemd-nspawn) that do not pass `/dev` through: build on the host itself, or in
WSL2 directly. On a host, check that the `loop` module is loaded (`sudo modprobe loop`).

**`error must run as root (chroot/mount needed): try 'sudo make <target>'`**

`packages`, `build` and `sd-image` need root, and the docs run `kernel` with `sudo` too so
everything under `build/` has one owner. `check`, `pending` and `sync` do not.
