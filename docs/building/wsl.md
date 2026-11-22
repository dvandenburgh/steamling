# Building on Windows with WSL2

WSL2 runs a real Linux kernel, so a Windows 10/11 PC builds Steamling the same way an x86_64 Linux
host does: the kernel cross-compiles, and the ARM build chroots run under qemu-user. This page
covers only what is different on WSL; [linux-host.md](linux-host.md) has the rest.

## 1. Install WSL and Ubuntu

In PowerShell **as administrator**:

```powershell
wsl --install -d Ubuntu-24.04
wsl --update
```

Reboot if asked, open **Ubuntu 24.04** from the Start menu and create your Linux user.

**systemd must be running** (it registers qemu with the kernel at every start). Ubuntu 24.04 on a
current WSL enables it by default; check with:

```bash
ps -p 1 -o comm=        # systemd
```

If it prints `init` instead, add this to `/etc/wsl.conf` in Ubuntu, then run `wsl --shutdown` in
PowerShell and reopen Ubuntu:

```ini
[boot]
systemd=true
```

## 2. Give WSL enough memory and disk

WSL2 gets half of the PC's RAM by default. The kernel build and the larger package builds can use
more than that, and an out-of-memory kill shows up as a random compiler crash. On a 16 GB PC, give
it most of the RAM and plenty of swap in `%UserProfile%\.wslconfig` (a Windows file):

```ini
[wsl2]
memory=12GB
swap=16GB
```

Then `wsl --shutdown` in PowerShell and reopen Ubuntu. If you still run out, lower the kernel
build's parallelism with `JOBS=4`.

The distro's virtual disk lives on `C:` by default and grows as the build fills it; it needs
**about 100 GB free**. To put it on another drive, run `wsl --shutdown`, then
`wsl --manage Ubuntu-24.04 --move D:\WSL\Ubuntu` in an administrator PowerShell.

## 3. Clone inside Linux, not on C:

```bash
cd ~ && git clone https://github.com/Steamling/steamling && cd steamling
```

**Do not build from `/mnt/c/...`.** Windows drives are mounted over a network-style filesystem with
no Unix owners or modes and case-insensitive names: the build chroots break on it, and it is many
times slower. `make check` flags it on its `checkout filesystem` line.

You can still edit on Windows: open the Linux clone from Windows at
`\\wsl.localhost\Ubuntu-24.04\home\<you>\steamling`, or in VS Code with `code .` from Ubuntu. If
you prefer to keep your main clone on the Windows side, see
[Editing on Windows, building in WSL](#editing-on-windows-building-in-wsl).

## 4. Host packages and the qemu flag

```bash
make host-setup
```

It installs the Ubuntu packages from [linux-host.md](linux-host.md#1-host-packages) and gives the
qemu registration the `C` flag Ubuntu leaves out ([why](linux-host.md#3-the-qemu-binfmt-c-flag-x86_64-hosts));
the fix survives `wsl --shutdown` and Windows reboots. It ends with `make check`: confirm every host
line says `ok`, including `btrfs (make sd-image)`.

Current WSL kernels include btrfs and loop devices. If `make check` reports btrfs `MISSING`, run
`wsl --update` in PowerShell, then `wsl --shutdown`, and check again.

## 5. Build

Exactly as on any Linux host - see the [Quick start](advanced.md#quick-start):

```bash
./build.sh                                   # -> build/image/sm8550/steamling-sm8550-sd.img
./build.sh --ssh                             # the same with SSH on, to reach it over the network
```

The bottom row of the terminal shows the step and the time left; `make watch` in a second Ubuntu
tab shows every step's progress.

A `wsl --shutdown` or a Windows Update reboot stops a running build. Run `./build.sh` again: `make build` keeps every package it already finished, and `make kernel` starts
its compile over (with ccache installed, the objects it already built come straight from the
cache).

## 6. Flash the image from Windows

The image is in your Linux home. Copy it somewhere Windows tools can open it:

```bash
cp build/image/sm8550/steamling-sm8550-sd.img /mnt/c/Users/<you>/Downloads/
```

Then flash `steamling-sm8550-sd.img` with **balenaEtcher** or **Rufus**, and follow
the [install guide](../install.md). (Explorer can also reach it
directly at `\\wsl.localhost\Ubuntu-24.04\home\<you>\steamling\build\image\sm8550\`.)

## Editing on Windows, building in WSL

If you work in a clone on the Windows side (for example `C:\Users\<you>\Git\steamling`), keep a
second clone in WSL that builds from it. Point the WSL clone at the Windows one once:

```bash
cd ~/steamling
git remote add win /mnt/c/Users/<you>/Git/steamling
```

Then, whenever you have committed on Windows and want to build it:

```bash
git fetch win && git checkout -B dev win/dev      # use your branch name
```

Only commit in the Windows clone, so the WSL clone never has work of its own to lose. Build
output (`build/`, `vendor/`) stays in WSL and is not affected by the checkout.
