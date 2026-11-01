# Building on a Linux host

Any recent x86_64 or aarch64 Linux works as a build host. You need root (the build uses chroots and
loop devices), about 100 GB free, and the packages below. On Windows, use [wsl.md](wsl.md), which
builds on this page.

## 1. Host packages

**Quickest:** `make host-setup` installs the packages below for a Debian/Ubuntu, Fedora or Arch
family distro (it uses `sudo`) and, on x86_64, applies the [qemu flag fix](#3-the-qemu-binfmt-c-flag-x86_64-hosts)
when it is needed. Or install them yourself:

**Ubuntu / Debian:**

```bash
sudo apt install build-essential bc flex bison python3 git rsync patch dwarves libssl-dev libelf-dev \
  cpio zstd xz-utils curl libarchive-tools parted gdisk dosfstools btrfs-progs ccache \
  gcc-aarch64-linux-gnu qemu-user-static
```

On **Ubuntu 26.04** and later, apt answers `Package 'qemu-user-static' has no installation
candidate`: it is only a placeholder name there. Put `qemu-user-binfmt` in its place, which installs
the same qemu and registers it. `make host-setup` picks the right one for you.

**Fedora:**

```bash
sudo dnf install make gcc bc flex bison python3 git rsync patch dwarves openssl-devel elfutils-libelf-devel \
  cpio zstd xz curl bsdtar parted gdisk dosfstools btrfs-progs ccache \
  gcc-aarch64-linux-gnu qemu-user-static-aarch64
```

**Arch Linux:**

```bash
sudo pacman -S --needed base-devel bc python git rsync pahole cpio zstd xz curl libarchive \
  parted gptfdisk dosfstools btrfs-progs ccache aarch64-linux-gnu-gcc qemu-user-static qemu-user-static-binfmt
```

On an **aarch64** host, leave out the cross compiler and qemu: everything runs natively. `ccache`
is optional: with it, `make kernel` after a small kernel change recompiles only what changed.

## 2. Check the host

```bash
make check
```

Besides validating the checkout, `make check` prints what an image build needs from this host:

```
  host arch                                    x86_64 (kernel cross-compiles, chroots run under qemu-user)
  cross compiler                               aarch64-linux-gnu-gcc ok
  qemu aarch64 binfmt                          POCF ok
  checkout filesystem                          ext2/ext3 ok
  btrfs (make sd-image)                        ok
```

Fix any line that says `MISSING` or `lacks C` before building.

## 3. The qemu binfmt `C` flag (x86_64 hosts)

On an x86_64 host the kernel runs the ARM chroot's programs through **qemu-user**, registered with
the kernel's `binfmt_misc`. Inside the package-build chroot, `makepkg` installs build dependencies
with `sudo`, and `sudo` can only become root if that registration has the **`C`** ("credentials")
flag. **Debian and Ubuntu register qemu-aarch64 without it** (`POF`), and the build stops with:

```
error binfmt qemu-aarch64 has flags 'POF', without C: sudo in the build chroot cannot gain root.
```

`make host-setup` does this for you. By hand: re-register it with `C` added. A file in
`/etc/binfmt.d/` with the same name as the distro's file in `/usr/lib/binfmt.d/` replaces it, and
survives reboots and package updates:

```bash
src="$(grep -l ':qemu-aarch64:' /usr/lib/binfmt.d/*.conf | head -n 1)"; echo "${src}"
sed 's/:\([A-Z]*\)$/:\1C/' "${src}" | sudo tee "/etc/binfmt.d/$(basename "${src}")"
sudo systemctl restart systemd-binfmt
grep flags /proc/sys/fs/binfmt_misc/qemu-aarch64      # flags: POCF
```

Only do this when `make check` says `lacks C`; on a registration that already has it, the `sed`
would add a second `C`.

## 4. Build

Follow the [Quick start](advanced.md#quick-start). In short:

```bash
./build.sh                                   # -> build/image/<soc>/steamling-<soc>-sd.img
```

(`make image` is the same; `./build.sh --help` lists the options), or step by step:

```bash
sudo make kernel && make pending
sudo make build && sudo make sd-image
```

## Notes

- **Keep the checkout on a normal Linux filesystem** (ext4, btrfs, xfs). The chroots need Unix
  owners, modes and device nodes, and the kernel tree needs case-sensitive names; `make check` flags
  a checkout on NTFS, FAT or a Windows drive.
- With a ROCKNIX checkout of your own at `../distribution`, `make sync` uses it instead of the
  pinned commit, and `STEAMLING_SYNC_SCOPE=all make sync` also refreshes the **committed** kernel
  inputs in `kernel/<soc>/` from it. That is how the maintainer moves the kernel pin; a plain build
  needs neither.
- The build chroot (`build/pkgbuild-root-<soc>/`) is created once, reused, and recreated by itself
  when the pinned base changes. If it ever gets into a bad state, make sure nothing is still
  mounted inside it (`findmnt | grep pkgbuild-root` prints nothing; on WSL, `wsl --shutdown`
  clears any leftovers), then remove only that directory:
  `sudo rm -rf build/pkgbuild-root-<soc>`. `rm -rf` follows bind mounts, so never skip the check.
  `make clean` removes far more: the kernel build and every package in `build/localrepo/`.
