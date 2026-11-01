#!/usr/bin/env bash
# host-setup.sh — install what an image build needs (docs/building/linux-host.md) on a Debian/
# Ubuntu, Fedora or Arch family host, and on x86_64 give qemu's aarch64 binfmt registration the C
# flag makepkg's sudo needs in the build chroot. Runs as you, with sudo for the installs.

source "$(dirname "$0")/lib.sh"
need_linux

as_root() { if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi; }
native=0; [ "$(uname -m)" = aarch64 ] && native=1

[ -r /etc/os-release ] || die "no /etc/os-release: install the packages in docs/building/linux-host.md yourself"
# shellcheck disable=SC1091
. /etc/os-release
family=""
for id in ${ID:-} ${ID_LIKE:-}; do
  case "${id}" in
    debian|ubuntu) family=debian; break ;;
    fedora) family=fedora; break ;;
    arch) family=arch; break ;;
  esac
done

case "${family}" in
  debian)
    pkgs=(build-essential bc flex bison python3 git rsync patch dwarves libssl-dev libelf-dev cpio zstd
          xz-utils curl libarchive-tools parted gdisk dosfstools btrfs-progs ccache)
    as_root apt-get update
    if [ "${native}" = 0 ]; then
      # Ubuntu 26.04 and newer Debian moved the static qemu into qemu-user and left qemu-user-static
      # a virtual package, which apt won't install by name. qemu-user-binfmt provides it there.
      qemu=qemu-user-static
      apt-cache show --no-all-versions "${qemu}" >/dev/null 2>&1 || qemu=qemu-user-binfmt
      pkgs+=(gcc-aarch64-linux-gnu "${qemu}")
    fi
    as_root apt-get install -y "${pkgs[@]}" ;;
  fedora)
    pkgs=(make gcc bc flex bison python3 git rsync patch dwarves openssl-devel elfutils-libelf-devel
          cpio zstd xz curl bsdtar parted gdisk dosfstools btrfs-progs ccache)
    [ "${native}" = 1 ] || pkgs+=(gcc-aarch64-linux-gnu qemu-user-static-aarch64)
    as_root dnf install -y "${pkgs[@]}" ;;
  arch)
    pkgs=(base-devel bc python git rsync pahole cpio zstd xz curl libarchive parted gptfdisk dosfstools
          btrfs-progs ccache)
    [ "${native}" = 1 ] || pkgs+=(aarch64-linux-gnu-gcc qemu-user-static qemu-user-static-binfmt)
    as_root pacman -S --needed --noconfirm "${pkgs[@]}" ;;
  *)
    die "'${PRETTY_NAME:-${ID:-this distro}}' is not a Debian/Ubuntu, Fedora or Arch family distro:
  install the packages in docs/building/linux-host.md yourself" ;;
esac

binfmt_flags() {  # flags of the loaded qemu-aarch64 registration, or nothing
  local entry
  entry="$(grep -l '^magic 7f454c46020101.*0200b700$' /proc/sys/fs/binfmt_misc/* 2>/dev/null | head -n 1 || true)"
  [ -n "${entry}" ] && grep -qx enabled "${entry}" && sed -n 's/^flags: //p' "${entry}"
}

# The same fix as linux-host.md's "qemu binfmt C flag": a file in /etc/binfmt.d/ named like the
# distro's own replaces it, so the flag survives reboots and qemu updates.
if [ "${native}" = 0 ] && [[ "$(binfmt_flags || true)" != *C* ]]; then
  [ -d /run/systemd/system ] || die "systemd is not running, and it is what registers qemu with the kernel.
  On WSL, add [boot] systemd=true to /etc/wsl.conf, run 'wsl --shutdown' in PowerShell, reopen
  Ubuntu and run 'make host-setup' again (docs/building/wsl.md)"
  src="$(grep -l ':qemu-aarch64:' /usr/lib/binfmt.d/*.conf 2>/dev/null | head -n 1 || true)"
  [ -n "${src}" ] || die "no qemu-aarch64 entry in /usr/lib/binfmt.d/: is qemu's binfmt part (qemu-user-static or qemu-user-binfmt) installed?"
  dst="/etc/binfmt.d/${src##*/}"
  if grep -q ':[A-Z]*C[A-Z]*$' "${src}"; then
    log "qemu-aarch64 binfmt: ${src} already has the C flag, reloading it"
  else
    log "qemu-aarch64 binfmt: adding the C flag in ${dst}"
    sed 's/:\([A-Z]*\)$/:\1C/' "${src}" | as_root tee "${dst}" >/dev/null
  fi
  as_root systemctl restart systemd-binfmt
  [[ "$(binfmt_flags || true)" == *C* ]] || die "qemu-aarch64 binfmt still lacks the C flag after the reload: see docs/building/linux-host.md"
fi

ok "host packages installed$([ "${native}" = 1 ] || printf ', qemu-aarch64 binfmt flags: %s' "$(binfmt_flags || true)")"
"${STEAMLING_ROOT}/scripts/check.sh" || true
