#!/usr/bin/env bash
# Shared helpers for steamling build scripts. Source this first:
#   source "$(dirname "$0")/lib.sh"
# It resolves STEAMLING_ROOT, loads config/steamling.conf, and defines utilities.

set -euo pipefail

# --- locate project root (parent of scripts/) ------------------------------
_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export STEAMLING_ROOT="$(cd "${_lib_dir}/.." && pwd)"

# Your own settings first (config/local.conf, never committed): steamling.conf only fills in
# what's still unset, so anything there wins. config/local.conf.example says what goes in it.
# The command line beats both: a value already set when we get here (build.sh's --device, or
# DEVICE=... make image) is put back after local.conf, which would otherwise overwrite it.
if [ -f "${STEAMLING_ROOT}/config/local.conf" ]; then
  _lc_keep=()
  while IFS= read -r _lc_name; do
    [ -n "${!_lc_name+x}" ] && _lc_keep+=("${_lc_name}=${!_lc_name}")
  done < <(sed -nE 's/^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=.*/\2/p' \
             "${STEAMLING_ROOT}/config/local.conf")
  source "${STEAMLING_ROOT}/config/local.conf"
  for _lc_kv in "${_lc_keep[@]}"; do printf -v "${_lc_kv%%=*}" '%s' "${_lc_kv#*=}"; done
  unset _lc_keep _lc_name _lc_kv
fi
# shellcheck source=../config/steamling.conf
source "${STEAMLING_ROOT}/config/steamling.conf"
# STEAMLING_BASE_SNAPSHOT=live builds straight from Arch Linux ARM's own repos, nothing frozen: ":="
# can't take an empty value from local.conf or the environment, so "live" is how you say none.
# STEAMLING_BASE_LIVE carries the choice through sudo, where an empty value would pin it again.
if [ "${STEAMLING_BASE_SNAPSHOT}" = live ] || [ "${STEAMLING_BASE_LIVE:-}" = 1 ]; then
  STEAMLING_BASE_SNAPSHOT=""
  export STEAMLING_BASE_LIVE=1
  # A cut base also pins the rootfs tarball to its own dated copy (make snapshot); live starts
  # from ALARM's latest instead. A tarball you chose yourself is left alone.
  case "${STEAMLING_ALARM_TARBALL_URL}" in
    "${STEAMLING_BASE_URL}"/*)
      ALARM_TARBALL=ArchLinuxARM-aarch64-latest.tar.gz
      STEAMLING_ALARM_SHA256=""
      STEAMLING_ALARM_TARBALL_URL="${ALARM_MIRROR}/${ALARM_TARBALL}" ;;
  esac
fi
# STEAMLING_BASE_URL is where a frozen base's pacman repo is hosted (it serves pocknix-base.db),
# not Arch Linux ARM's tarball. Pointing it there 404s halfway through, so say so up front.
case "${STEAMLING_BASE_URL:-}" in
  *.tar.gz|*.tar.xz|*.tar|*os.archlinuxarm.org*)
    printf 'error STEAMLING_BASE_URL=%s is not a frozen base. To build from live Arch Linux ARM,\n' "${STEAMLING_BASE_URL}" >&2
    printf '      remove that line and set STEAMLING_BASE_SNAPSHOT=live in config/local.conf instead.\n' >&2
    exit 1 ;;
esac

# --- device profile + per-SoC kernel pins -----------------------------------
# The device profile (devices/<name>/profile.conf) declares what differs per family: SoC,
# boot style, kernel cmdline, GPU sensor. It sets SOC, which selects the per-SoC kernel tree
# and its source pins (kernel/<soc>/kernel.conf).
if [ ! -f "${STEAMLING_ROOT}/devices/${DEVICE}/profile.conf" ]; then
  printf 'error: unknown DEVICE=%s — available: %s\n' \
    "${DEVICE}" "$(ls "${STEAMLING_ROOT}/devices" 2>/dev/null | tr '\n' ' ')" >&2
  exit 1
fi
# Profile defaults that derive from the profile's own keys, so they run after it; a profile
# sets any of them to override. The SoC-neutral ones live in config/steamling.conf instead,
# because a profile expands them (ROOT_LABEL in its cmdline) while it is being sourced, so a
# profile overrides those with a plain X=value.
profile_defaults() {
  : "${KERNEL_CMDLINE:=${KERNEL_CMDLINE_ROOT} ${KERNEL_CMDLINE_EXTRA}}"
  : "${DEVICE_BSP_PKG:=steamling-bsp-${SOC}}"
  : "${DEVICE_META_PKG:=steamling-device-${SOC}}"
  : "${KERNEL_PKG:=linux-steamling-${SOC}}"
}
source "${STEAMLING_ROOT}/devices/${DEVICE}/profile.conf"
profile_defaults
source "${STEAMLING_ROOT}/kernel/${SOC}/kernel.conf"
# Per-SoC userspace compiler tuning: the tuned packages/soc PKGBUILDs read these
# (build-packages.sh injects them into every packages/soc makepkg environment).
source "${STEAMLING_ROOT}/devices/${DEVICE}/tuning.conf"

# Paths derived from the profile (must come after it):
: "${DEVICE_DIR:=${STEAMLING_ROOT}/devices/${DEVICE}}"
: "${KERNEL_DIR:=${STEAMLING_ROOT}/kernel/${KERNEL_TREE:-${SOC}}}"   # KERNEL_TREE: a tree several SoCs share
: "${ROCKNIX_DEVICE_DIR:=${ROCKNIX_PROJECT_DIR}/devices/${ROCKNIX_SOC:-}}"
# Per-SoC pacman repo: tuned packages (mesa etc.) share pkgnames across SoCs
# with different binaries, so each SoC gets its own localrepo/published tree.
# packages/shared/* are byte-identical across SoCs: built once into the shared
# localrepo, published once as [steamling-shared] (repo membership doubles as
# delivery targeting).
: "${LOCALREPO_DIR:=${BUILD_DIR}/localrepo/${SOC}}"
: "${LOCALREPO_SHARED_DIR:=${BUILD_DIR}/localrepo/shared}"
# Publish staging area (stage-repo.sh): a mirror of the LIVE repo with only the
# intended packages swapped in — publish-repo.sh publishes THIS, never the
# raw localrepo (which parallel sessions fill with unvalidated builds).
: "${STAGE_DIR:=${BUILD_DIR}/stage/${SOC}}"
# Which repo tree stage-repo.sh/publish-repo.sh operate on: the per-SoC
# [steamling] tree (default) or the SoC-neutral [steamling-shared] tree
# (make stage-shared / publish-shared). The db filename must equal the repo
# tag, hence REPO_NAME drives both the stanza and the *.db names.
: "${STEAMLING_REPO_SCOPE:=soc}"
if [ "${STEAMLING_REPO_SCOPE}" = "shared" ]; then
  REPO_NAME="steamling-shared"; REPO_SEG="shared"
  REPO_LOCALREPO_DIR="${LOCALREPO_SHARED_DIR}"
  REPO_STAGE_DIR="${BUILD_DIR}/stage/shared"
else
  REPO_NAME="steamling"; REPO_SEG="${SOC}"
  REPO_LOCALREPO_DIR="${LOCALREPO_DIR}"
  REPO_STAGE_DIR="${STAGE_DIR}"
fi
# Per-SoC kernel + image outputs, so switching families never forces a kernel rebuild
# or mixes one family's out/ with another's. (build/cache and build/rootfs stay shared:
# the cache is SoC-neutral downloads, the rootfs is wiped by bootstrap.sh on every build.)
: "${KERNEL_BUILD_DIR:=${BUILD_DIR}/kernel/${SOC}}"
: "${IMAGE_DIR:=${BUILD_DIR}/image/${SOC}}"

# --- logging ---------------------------------------------------------------
_c_blue=$'\033[1;34m'; _c_grn=$'\033[1;32m'; _c_yel=$'\033[1;33m'
_c_red=$'\033[1;31m';  _c_rst=$'\033[0m'
log()  { printf '%s==>%s %s\n'  "$_c_blue" "$_c_rst" "$*"; }
ok()   { printf '%s ok%s %s\n'  "$_c_grn"  "$_c_rst" "$*"; }
warn() { printf '%swarn%s %s\n' "$_c_yel"  "$_c_rst" "$*" >&2; }
die()  { printf '%serror%s %s\n' "$_c_red" "$_c_rst" "$*" >&2; exit 1; }

# --- guards ----------------------------------------------------------------
need_root() { [ "$(id -u)" -eq 0 ] || die "must run as root (chroot/mount needed): try 'sudo make $1'"; }
need_linux() { [ "$(uname -s)" = "Linux" ] || die "the image build must run on a Linux host (current: $(uname -s)). Use a Linux box or container."; }
have()     { command -v "$1" >/dev/null 2>&1; }
need_tool(){ have "$1" || die "missing required tool: $1"; }

# --- on/off knobs ------------------------------------------------------------
# The switches take 1/on/yes/true and 0/off/no/false in any case. Anything else dies: a typo like
# SD_SSH=1 used to read as "off" and only showed up as a refused login on the device.
onoff() {  # <name> <value> -> "on" or "off"
  case "${2,,}" in
    1|on|yes|y|true) printf on ;;
    0|off|no|n|false|"") printf off ;;
    *) die "$1='$2': expected on or off (1/0, yes/no and true/false work too)" ;;
  esac
}
# SSH=1 is the short spelling of SD_SSH=on (make image SSH=1, ./build.sh --ssh) and wins when both
# are set. A non-boolean SSH (some shells export it as a command name) is not ours: it is ignored.
case "${SSH:-}" in
  "") SD_SSH="$(onoff SD_SSH "${SD_SSH}")" ;;
  *)
    case "${SSH,,}" in
      1|0|on|off|y|n|yes|no|true|false) SD_SSH="$(onoff SSH "${SSH}")" ;;
      *) warn "ignoring SSH='${SSH}' (not on/off); SD_SSH=${SD_SSH} decides"
         SD_SSH="$(onoff SD_SSH "${SD_SSH}")" ;;
    esac ;;
esac

# --- package lists ---------------------------------------------------------
# awk $1, not sed 's/#.*//': sed keeps the whitespace before an inline comment and
# pacman then can't match the name.
# A variable as one family's build resolves it (local.conf, steamling.conf, its profile, the defaults), in a
# clean environment: everything assigns with ":=", so the selected DEVICE's values would win.
profile_get() {  # $1 = devices/<soc> dir, $2 = variable name
  env -i STEAMLING_ROOT="${STEAMLING_ROOT}" bash -c "$(declare -f profile_defaults)"'
    { [ ! -f "${STEAMLING_ROOT}/config/local.conf" ] || . "${STEAMLING_ROOT}/config/local.conf"; } &&
    . "${STEAMLING_ROOT}/config/steamling.conf" && . "$1/profile.conf" && profile_defaults && printf "%s" "${!2:-}"' sh "$1" "$2"
}

read_pkglist() {
  awk '{ sub(/#.*/, ""); if ($1 != "") print $1 }' "$1"
}

# --- chroot mount/teardown (idempotent) ------------------------------------
# Every mount only once, and the /dev binds private. On a systemd host (WSL with systemd=true
# included) every mount is shared, so a bind of /dev is a PEER of the host's /dev and whatever is
# mounted on or under it lands on the host too: a second bind over an interrupted build's leftovers
# covers the host's /dev/pts, and from then on nothing opens a terminal (sudo: "unable to allocate
# pty: No such device") until the mounts go or the machine restarts.
chroot_bind() {  # <source> <target>
  mountpoint -q "$2" && return 0
  mount --bind "$1" "$2"
  mount --make-private "$2"
}
chroot_mount() {
  local root="$1"
  chroot_bind /dev     "${root}/dev"
  chroot_bind /dev/pts "${root}/dev/pts"
  mountpoint -q "${root}/proc" || mount -t proc  proc  "${root}/proc"
  mountpoint -q "${root}/sys"  || mount -t sysfs sys   "${root}/sys"
  mountpoint -q "${root}/run"  || mount -t tmpfs tmpfs "${root}/run"
  chroot_resolv "${root}"
  # One package cache for the rootfs and every build chroot, so pacman fetches each file once
  # rather than once per chroot and per build. Files a chroot cached itself move into it.
  local pc="${root}/var/cache/pacman/pkg"
  if ! mountpoint -q "${pc}"; then
    mkdir -p "${PKG_CACHE_DIR}" "${pc}"
    find "${pc}" -maxdepth 1 -type f -name '*.pkg.tar.*' ! -name '*.part' \
      -exec mv -n -t "${PKG_CACHE_DIR}" {} + 2>/dev/null || true
    mount --bind "${PKG_CACHE_DIR}" "${pc}"
  fi
  prune_localrepo_copies
}

# pacman caches its file:// installs from build/localrepo too. A package rebuilt at the same version
# would then fail its checksum against the stale copy, so those never outlive a chroot session.
prune_localrepo_copies() {
  local f
  for f in "${LOCALREPO_DIR}"/*.pkg.tar.* "${LOCALREPO_SHARED_DIR}"/*.pkg.tar.*; do
    if [ -f "${f}" ]; then rm -f "${PKG_CACHE_DIR}/${f##*/}"; fi
  done
}

# Anything mounted below <dir>? Captured first: under pipefail a SIGPIPE'd findmnt | grep -q would
# read as "nothing mounted", and rm -rf follows bind mounts.
mounted_under() {
  local mounts
  mounts="$(findmnt -rno TARGET)" || return 0
  grep -q "^$1/" <<< "${mounts}"
}

# Give the chroot a working /etc/resolv.conf. On systemd-resolved hosts (Fedora,
# Arch, etc.) the host /etc/resolv.conf is a stub pointing at 127.0.0.53, which
# resolves nothing inside the chroot — so prefer the real upstream resolvers, and
# fall back to public DNS if only a localhost stub is available.
chroot_resolv() {
  local root="$1" src
  for src in /run/systemd/resolve/resolv.conf /etc/resolv.conf; do
    if [ -e "$src" ]; then
      rm -f "${root}/etc/resolv.conf"
      cp -L "$src" "${root}/etc/resolv.conf"
      break
    fi
  done
  # no -q on the last grep: it reads to the end, so pipefail can't see a SIGPIPE'd first grep
  if ! grep -E '^[[:space:]]*nameserver' "${root}/etc/resolv.conf" 2>/dev/null | grep -v '127\.' >/dev/null; then
    warn "no usable upstream resolver found in chroot — falling back to public DNS (1.1.1.1)"
    printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > "${root}/etc/resolv.conf"
  fi
}

# Every mount below <root>, not just the ones chroot_mount makes: an interrupted build also leaves
# /localrepo{,-shared} and the Steam bake's /dev/shm, and builds before the private binds stacked
# /dev twice. Deepest first, each made private before it goes so the unmount cannot propagate to
# the host's /dev, and repeated until nothing is left (a stacked mount needs one pass per layer).
unmount_under() {  # <root>; fails if anything is still mounted below it
  local root="$1" t _
  for _ in 1 2 3 4 5 6 7 8; do
    mounted_under "${root}" || return 0
    while IFS= read -r t; do
      mount --make-private "${t}" 2>/dev/null || true
      umount -l "${t}" 2>/dev/null || true
    done < <(findmnt -rno TARGET | awk -v r="${root}/" 'index($0, r) == 1 { print length($0) "\t" $0 }' \
               | sort -rn | cut -f2-)
  done
  ! mounted_under "${root}"
}

chroot_umount() {
  local root="$1"
  unmount_under "${root}" || warn "still mounted under ${root} after unmounting: $(findmnt -rno TARGET | grep "^${root}/" | tr '\n' ' ')"
  prune_localrepo_copies
}

# Put the host's qemu-aarch64 into the rootfs when cross-building from x86_64.
maybe_install_qemu() {
  local root="$1" entry flags interp src
  [ "$(uname -m)" = "aarch64" ] && return 0   # native, nothing to do
  # The chroots run under qemu via binfmt_misc, and makepkg's `sudo pacman` only gains root if
  # the handler has flag C. Debian/Ubuntu register qemu-aarch64 without it (it shows POF).
  entry="$(grep -l '^magic 7f454c46020101.*0200b700$' /proc/sys/fs/binfmt_misc/* 2>/dev/null | head -n 1 || true)"
  { [ -n "${entry}" ] && grep -qx enabled "${entry}"; } \
    || die "no enabled aarch64 binfmt handler on $(uname -m): install qemu-user-static (qemu-user-binfmt on Ubuntu 26.04 and later) with its binfmt registration (systemd-binfmt or binfmt-support)"
  flags="$(sed -n 's/^flags: //p' "${entry}")"
  case "${flags}" in
    *C*) ;;
    *) die "binfmt ${entry##*/} has flags '${flags}', without C: sudo in the build chroot cannot gain root.
  Copy its line from /usr/lib/binfmt.d/ into /etc/binfmt.d/ with 'C' added to the flags, then run
  'systemctl restart systemd-binfmt'" ;;
  esac
  # The registration names the qemu it runs: qemu-aarch64-static on most distros, plain
  # qemu-aarch64 where qemu-user itself is static (Ubuntu 26.04, Debian's newer qemu). Copy that
  # one to the same path in the chroot, for a registration without the F flag.
  interp="$(sed -n 's/^interpreter //p' "${entry}")"
  src="${interp:-${QEMU_AARCH64_STATIC}}"
  [ -f "${src}" ] || src="${QEMU_AARCH64_STATIC}"
  [ -f "${src}" ] || die "cross-building on $(uname -m) needs ${interp:-${QEMU_AARCH64_STATIC}}, the qemu the aarch64 binfmt handler runs: reinstall qemu-user-static (qemu-user-binfmt on Ubuntu 26.04 and later)"
  install -Dm755 "${src}" "${root}${interp:-${QEMU_AARCH64_STATIC}}"
}

# --- pinned ALARM base ------------------------------------------------------
# Fetch + verify the ALARM base tarball into CACHE_DIR. One implementation for
# bootstrap.sh (rootfs) and build-packages.sh (build chroot), so the two bases cannot diverge.
fetch_alarm_tarball() {
  local tarball="${CACHE_DIR}/${ALARM_TARBALL}" md5=""
  mkdir -p "${CACHE_DIR}"
  # Unpinned: ALARM's rolling "latest" keeps its name when it moves, so the cached copy is
  # checked against the .md5 ALARM publishes beside it and fetched again when it differs.
  if [ -z "${STEAMLING_ALARM_SHA256}" ]; then
    md5="$(curl -fsSL --retry 3 "${STEAMLING_ALARM_TARBALL_URL}.md5" 2>/dev/null | awk 'NR==1{print $1}')"
    if [ -z "${md5}" ]; then
      warn "could not read ${STEAMLING_ALARM_TARBALL_URL}.md5 — using the tarball as is"
    elif [ -f "${tarball}" ] && ! echo "${md5}  ${tarball}" | md5sum -c - >/dev/null 2>&1; then
      log "ALARM has published a new ${ALARM_TARBALL}; replacing the cached copy"
      rm -f "${tarball}"
    fi
  fi
  if [ ! -f "${tarball}" ]; then
    log "downloading ALARM rootfs: ${STEAMLING_ALARM_TARBALL_URL}"
    curl -fL --retry 3 -o "${tarball}" "${STEAMLING_ALARM_TARBALL_URL}"
  else
    log "using cached ALARM rootfs: ${tarball}"
  fi
  if [ -n "${STEAMLING_ALARM_SHA256}" ]; then
    echo "${STEAMLING_ALARM_SHA256}  ${tarball}" | sha256sum -c - >/dev/null \
      || die "ALARM tarball sha256 mismatch — refusing to build"
    ok "ALARM tarball checksum verified"
  else
    if [ -n "${md5}" ]; then
      echo "${md5}  ${tarball}" | md5sum -c - >/dev/null \
        || die "ALARM tarball does not match ${STEAMLING_ALARM_TARBALL_URL}.md5 (truncated download?) — delete ${tarball} and retry"
      ok "ALARM tarball matches its published md5"
    fi
    warn "STEAMLING_ALARM_SHA256 is unset — build is NOT reproducible (pin it for releases)"
  fi
}

# pacman's sync-upgrade flags for a base chroot: with a frozen base pinned, -Syuu, so packages
# the ALARM tarball carries at other versions are moved onto exactly what the base serves
# (downgrades included); live ALARM: plain -Syu.
base_sync_flags() {
  if [ -n "${STEAMLING_BASE_SNAPSHOT}" ]; then printf -- '-Syuu'; else printf -- '-Syu'; fi
}

# Render the base pacman.conf: with a pinned snapshot, the only package source
# is the frozen [pocknix-base] repo (ALARM's per-package .sig files are kept in
# the snapshot, so package SigLevel stays Required; the repo-add DB is unsigned,
# which DatabaseOptional permits). Without a pin: live ALARM. Shared
# by the rootfs and the build chroot so both always install from the SAME base.
render_base_pacman_conf() {
  local out="$1"
  if [ -n "${STEAMLING_BASE_SNAPSHOT}" ]; then
    # keep the template's [options] block, replace every repo with the snapshot
    sed '/^\[core\]$/,$d' "${CONFIG_DIR}/pacman.conf.in" > "${out}"
    cat >> "${out}" <<EOF
[pocknix-base]
SigLevel = Required DatabaseOptional
Server = ${STEAMLING_BASE_URL}
EOF
  else
    cp -f "${CONFIG_DIR}/pacman.conf.in" "${out}"
  fi
}

# Files outside a package's dir that it is also built from (build_one stages what they render
# into ./staged), so editing one rebuilds it like an edit to its own dir. steamling.conf holds the
# SD labels; kernel.conf the kernel package's version and release.
pkg_extra_srcs() {  # $1 = package name
  case "$1" in
    "${DEVICE_BSP_PKG}") echo "${DEVICE_DIR}/profile.conf ${CONFIG_DIR}/steamling.conf ${STEAMLING_ROOT}/scripts/render-bsp.sh" ;;
    "steamling-bootloader-${SOC}") echo "${DEVICE_DIR}/profile.conf ${CONFIG_DIR}/steamling.conf" ;;
    # kernel/<soc>/, not KERNEL_DIR: a SoC on a shared tree keeps its kernel.conf in its own dir.
    "${KERNEL_PKG}") echo "${STEAMLING_ROOT}/kernel/${SOC}/kernel.conf" ;;
  esac
}

# The name a package dir builds as, which PKG= selects and the skip and staging key on. The
# kernel recipe is one dir for every SoC, so it takes the current SoC's package name.
pkg_name() {  # $1 = package dir
  case "${1%/}" in
    */packages/soc/linux-steamling) printf '%s' "${KERNEL_PKG}" ;;
    */packages/soc/steamling-bootloader) printf 'steamling-bootloader-%s' "${SOC}" ;;
    *) basename "$1" ;;
  esac
}

# makepkg's environment for a package dir. Every makepkg call needs it, --packagelist included:
# the kernel recipe's name and version come from it. Shared packages get NO SoC/tuning env: they
# must be byte-stable whichever SoC's run builds them. STEAMLING_BASE_*: steamling-lock-migrate stamps
# the target snapshot URL into its script, so snapshot bumps re-target the migrator on rebuild.
pkg_env() {  # $1 = package dir
  printf ' %s=%q' STEAMLING_BASE_URL "${STEAMLING_BASE_URL}" STEAMLING_BASE_SNAPSHOT "${STEAMLING_BASE_SNAPSHOT}"
  case "$1" in */packages/shared/*) return ;; esac
  printf ' %s=%q' \
    STEAMLING_SOC "${SOC}" \
    STEAMLING_TUNE_CFLAGS "${STEAMLING_TUNE_CFLAGS}" \
    STEAMLING_FEX_TUNE_CPU "${STEAMLING_FEX_TUNE_CPU}" \
    STEAMLING_BOOTLOADER "${BOOTLOADER}" \
    STEAMLING_KERNEL_PKG "${KERNEL_PKG}" \
    STEAMLING_KERNEL_VERSION "${KERNEL_VERSION}" \
    STEAMLING_KERNEL_PKGREL "${KERNEL_PKGREL:-}" \
    STEAMLING_KERNEL_LEGACY_NAMES "${KERNEL_LEGACY_NAMES:-}"
}

# Every artifact `make build` wants for this SOC, one "repo-dir|pkg-dir|pkgname|version|arch"
# line each: build-packages.sh's dirs, socs gating and makepkg --packagelist naming, read from
# the PKGBUILDs alone so pending.sh and seed-localrepo.sh need no build chroot.
local_artifacts() {
  local d devsoc socs repo
  for d in "${PACKAGES_DIR}"/shared/*/ "${PACKAGES_DIR}"/soc/*/ "${STEAMLING_ROOT}"/devices/*/packages/*/; do
    [ -f "${d}PKGBUILD" ] || continue
    case "${d}" in */devices/*/packages/*)
      devsoc="$(unset SOC; . "${d%/packages/*}/profile.conf" >/dev/null 2>&1; printf '%s' "${SOC}")"
      [ "${devsoc}" = "${SOC}" ] || continue
    ;; esac
    case "${d}" in
      */packages/soc/*)
        socs=""; read -r socs 2>/dev/null < "${d}socs" || true
        case " ${socs} " in " all "|*" ${SOC} "*) ;; *) continue ;; esac ;;
    esac
    repo="${LOCALREPO_DIR}"
    case "${d}" in */packages/shared/*) repo="${LOCALREPO_SHARED_DIR}" ;; esac
    # PKGBUILDs are not written for set -eu, and some read ${startdir} like makepkg sets it; the
    # kernel recipe takes its name and version from pkg_env, as makepkg gets them.
    # shellcheck disable=SC2034,SC2154  # the sourced PKGBUILD sets arch, pkgname, pkgver, pkgrel
    (
      eval "export $(pkg_env "${d}")"
      cd "${d}" && set +eu && startdir="${PWD}" && source ./PKGBUILD >/dev/null 2>&1
      a=aarch64; [[ " ${arch[*]} " == *" any "* ]] && a=any
      for p in "${pkgname[@]}"; do
        printf '%s|%s|%s|%s|%s\n' "${repo}" "${d%/}" "${p}" "${epoch:+${epoch}:}${pkgver}-${pkgrel}" "${a}"
      done
    )
  done
}

# The file in <repo-dir> for <name-version-arch>, never a signature or a partial download.
artifact_file() {  # <repo-dir> <name-version-arch>
  local f
  for f in "$1/$2.pkg.tar."*; do
    case "${f}" in *.sig|*.part) continue ;; esac
    [ -f "${f}" ] && { printf '%s\n' "${f}"; return 0; }
  done
  return 1
}

# Every artifact of every package dir `make build` would compile, as local_artifacts lines. Its
# skip rule, read from the PKGBUILDs alone: a dir is up to date only when every artifact it names
# is in build/localrepo, newer than every file in the dir (and, for the kernel package, than
# `make kernel`'s Image). STEAMLING_FORCE_REBUILD=1 compiles everything, as it does there.
# build_one's skip rule for one built artifact: newer than every file in its package dir and
# every extra source (pkg_extra_srcs), and for the kernel package newer than `make kernel`'s Image.
artifact_current() {  # <artifact file> <package dir> <package name>
  local s
  [ -z "$(find "$2" -newer "$1" -print -quit)" ] || return 1
  for s in $(pkg_extra_srcs "$3"); do [ "${s}" -nt "$1" ] && return 1; done
  ! { [ "$3" = "${KERNEL_PKG}" ] && [ "${KERNEL_BUILD_DIR}/out/Image" -nt "$1" ]; }
}

# Which base each built package was linked against, kept beside (not in) the local repos so
# nothing that syncs a repo picks it up: build/built-base/<repo>/<name-ver-rel-arch> holds the id.
BUILT_BASE_DIR="${BUILD_DIR}/built-base"
built_base_file() {  # <repo dir> <artifact file or name-ver-rel-arch>
  local a="${2##*/}"
  printf '%s/%s/%s' "${BUILT_BASE_DIR}" "${1##*/}" "${a%.pkg.tar.*}"
}
stamp_built_base() {  # <repo dir> <base id> <artifact>...
  local repo="$1" b="$2" a
  shift 2
  mkdir -p "${BUILT_BASE_DIR}/${repo##*/}"
  for a in "$@"; do printf '%s\n' "${b}" > "$(built_base_file "${repo}" "${a}")"; done
  _progress_own "${BUILT_BASE_DIR}" "${BUILT_BASE_DIR}/${repo##*/}"
}
# A native package built against another base links sonames this one may not have (the protobuf
# bump that broke scx-scheds), so it counts as stale. arch=any packages carry no binaries. With no
# record yet, the build chroot's base is the best guess: it's what built the package.
artifact_on_base() {  # <repo dir> <artifact file>
  local b want="${STEAMLING_BASE_SNAPSHOT:-live}"
  case "$2" in *-any.pkg.tar.*) return 0 ;; esac
  b="$(cat "$(built_base_file "$1" "$2")" 2>/dev/null)" \
    || b="$(cat "${BUILD_DIR}/pkgbuild-root-${SOC}/.base-snapshot" 2>/dev/null)" || return 0
  [ -z "${b}" ] || [ "${b}" = "${want}" ]
}

pending_artifacts() {
  local -A stale=()
  local -a want=()
  local line repo d p v a f
  mapfile -t want < <(local_artifacts)
  for line in "${want[@]}"; do
    IFS='|' read -r repo d p v a <<< "${line}"
    [ -z "${stale[${d}]:-}" ] || continue
    [ "${STEAMLING_FORCE_REBUILD:-0}" != 1 ] \
      && f="$(artifact_file "${repo}" "${p}-${v}-${a}")" \
      && artifact_current "${f}" "${d}" "${p}" \
      && artifact_on_base "${repo}" "${f}" \
      || stale[${d}]=1
  done
  for line in "${want[@]}"; do
    IFS='|' read -r repo d p v a <<< "${line}"
    [ -z "${stale[${d}]:-}" ] || printf '%s\n' "${line}"
  done
}

# --- build progress ------------------------------------------------------------
# make image keeps a status file (STEAMLING_PROGRESS_FILE, exported to every step) that its status
# bar and `make status` read, and a per-host history of how long each step and each package took,
# which is where its time-left estimate comes from. Best effort throughout: no write here can fail
# a build, and outside make image the status writes do nothing.
: "${PROGRESS_DIR:=${BUILD_DIR}/progress}"
PROGRESS_HISTORY="${PROGRESS_DIR}/history-${SOC}"   # "<key> <seconds>": the last time each took

now_s() { printf '%(%s)T' -1; }
fmt_dur() {  # <seconds> -> 45s | 12m05s | 2h03m
  local s="${1:-0}"
  [[ "${s}" =~ ^[0-9]+$ ]] || s=0
  if [ "${s}" -lt 60 ]; then printf '%ds' "${s}"
  elif [ "${s}" -lt 3600 ]; then printf '%dm%02ds' $((s / 60)) $((s % 60))
  else printf '%dh%02dm' $((s / 3600)) $((s % 3600 / 60)); fi
}

# Files a root step writes here go back to whoever ran sudo: the next run's first steps run as them.
_progress_own() {
  [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_UID:-}" ] || return 0
  chown "${SUDO_UID}:${SUDO_GID:-${SUDO_UID}}" "$@" 2>/dev/null || true
}

# <file> <awk filter> <new lines>: rewrite a small state file in one rename, so a reader never
# sees half of it.
_progress_rewrite() {
  local f="$1" keep="$2" add="$3" tmp
  mkdir -p "${f%/*}" 2>/dev/null || return 0
  _progress_own "${f%/*}"
  tmp="$(mktemp "${f}.XXXXXX" 2>/dev/null)" || return 0
  if { [ ! -f "${f}" ] || awk "${keep}" "${f}"; printf '%s' "${add}"; } > "${tmp}" 2>/dev/null \
     && chmod 644 "${tmp}" && mv -f "${tmp}" "${f}"; then
    _progress_own "${f}"
  else
    rm -f "${tmp}"
  fi
  return 0
}

progress_set() {  # <KEY> <value> [<KEY> <value> ...]: update the running build's status file
  local f="${STEAMLING_PROGRESS_FILE:-}" keys="" add="" k v
  [ -n "${f}" ] || return 0
  while [ "$#" -ge 2 ]; do
    k="$1"; v="${2//$'\n'/ }"; shift 2
    keys+="${keys:+|}${k}"; add+="${k}=${v}"$'\n'
  done
  _progress_rewrite "${f}" "!/^(${keys})=/" "${add}"
}
progress_detail() { progress_set P_DETAIL "$*"; }

hist_get() {  # <key> -> seconds it took last time; nothing when it never ran here
  [ -f "${PROGRESS_HISTORY}" ] || return 0
  awk -v k="$1" '$1 == k && $2 ~ /^[0-9]+$/ { v = $2 } END { if (v != "") print v }' \
    "${PROGRESS_HISTORY}" 2>/dev/null || true
}
hist_set() {  # <key> <seconds>
  [[ "$2" =~ ^[0-9]+$ ]] || return 0
  _progress_rewrite "${PROGRESS_HISTORY}" "\$1 != \"$1\"" "$1 $2"$'\n'
}

# How long one package should take to build: its own last build here, else a guess - an arch=any
# package only lays out files, anything else compiles (several times slower under qemu).
pkg_estimate() {  # <package dir name> <any|native> -> "<seconds> <1 when guessed>"
  local h; h="$(hist_get "pkg.$1")"
  if [ -n "${h}" ]; then printf '%s 0\n' "${h}"; return 0; fi
  case "$2:$(uname -m)" in
    any:*) printf '60 1\n' ;;
    *:aarch64) printf '300 1\n' ;;
    *) printf '1200 1\n' ;;
  esac
}
