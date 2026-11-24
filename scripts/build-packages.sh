#!/usr/bin/env bash
# build-packages.sh — build the local steamling-* packages with makepkg.
#
# The host (Fedora) has no makepkg, so we build inside a dedicated Arch Linux ARM
# build chroot (base-devel). Results + pacman repo DBs land in ${LOCALREPO_DIR} (per-SoC)
# and ${LOCALREPO_SHARED_DIR}, which build-image.sh consumes as [steamling] + [steamling-shared].
#
# Standalone: `sudo make packages`.
# Needs a Linux host + root (chroot/mount); native makepkg on aarch64, qemu on x86.

source "$(dirname "$0")/lib.sh"
need_linux
need_root build-packages
for t in curl tar rsync; do need_tool "$t"; done

# Two repo trees: packages/soc/* are PER-SoC (tuned packages share
# pkgnames across SoCs with different binaries; each SoC gets its own repo, and the
# chroot is split too so one SoC's tuned makedepends can never leak into
# another SoC's builds). packages/shared/* are byte-identical across SoCs:
# built ONCE into the shared localrepo ([steamling-shared]) — whichever SoC runs
# first builds them, the other run's incremental skip sees them up to date.
BROOT="${BUILD_DIR}/pkgbuild-root-${SOC}"   # the makepkg build chroot (reused across runs)
LOCALREPO="${LOCALREPO_DIR}"                # build/localrepo/${SOC} (set in lib.sh)
LOCALREPO_SHARED="${LOCALREPO_SHARED_DIR}"  # build/localrepo/shared (set in lib.sh)
TARBALL="${CACHE_DIR}/${ALARM_TARBALL}"
REPO_DB="steamling.db.tar.gz"
SHARED_REPO_DB="steamling-shared.db.tar.gz"

cleanup() { mountpoint -q "${BROOT}/build/ccache" && umount "${BROOT}/build/ccache" 2>/dev/null || true
            chroot_umount "${BROOT}" 2>/dev/null || true
            mountpoint -q "${BROOT}/localrepo" && umount "${BROOT}/localrepo" 2>/dev/null || true
            mountpoint -q "${BROOT}/localrepo-shared" && umount "${BROOT}/localrepo-shared" 2>/dev/null || true; }
trap cleanup EXIT

# rm -rf follows bind mounts (even --one-file-system: same device), so a localrepo mount left
# by an interrupted build would take the real localrepo with it. Never rm with one in place.
wipe_chroot() {
  cleanup
  ! mounted_under "${BROOT}" || die "still mounted under ${BROOT}, not wiping it"
  rm -rf "${BROOT}"
}

# Which repo a package dir builds into: shared packages target the shared
# localrepo, everything else (packages/soc + device packages) the per-SoC one.
pkg_repo_dir()   { case "$1" in */packages/shared/*) printf '%s' "${LOCALREPO_SHARED}" ;; *) printf '%s' "${LOCALREPO}" ;; esac; }
pkg_repo_db()    { case "$1" in */packages/shared/*) printf '%s' "${SHARED_REPO_DB}" ;; *) printf '%s' "${REPO_DB}" ;; esac; }
pkg_repo_mount() { case "$1" in */packages/shared/*) printf '/localrepo-shared' ;; *) printf '/localrepo' ;; esac; }

# make image's status bar: the compiles still to come (pending_artifacts, before any skip check)
# with how long each should take, so the step's end can be re-estimated as packages finish.
declare -A PKG_LEFT=()
PKG_TOTAL=0 PKG_STARTED=0 PKG_SECS=0 PKG_DIRS=0 PKG_CHECKED=0
progress_pkgs_init() {
  [ -n "${STEAMLING_PROGRESS_FILE:-}" ] || return 0
  local -A kind=()
  local d a n
  # Every package dir gets a skip check (makepkg --packagelist in the chroot: seconds each under
  # qemu, minutes for the lot), so the bar counts them too.
  PKG_DIRS="$(local_artifacts | cut -d'|' -f2 | sort -u | wc -l)"
  while IFS='|' read -r _ d _ _ a; do
    n="$(pkg_name "${d}")"   # the name progress_pkg and the history key on
    [ "${a}" = any ] && [ "${kind[${n}]:-}" != native ] && kind[${n}]=any || kind[${n}]=native
  done < <(pending_artifacts)
  for n in "${!kind[@]}"; do
    read -r "PKG_LEFT[${n}]" _ < <(pkg_estimate "${n}" "${kind[${n}]}")
  done
  PKG_TOTAL="${#PKG_LEFT[@]}"
}
# <name> started | <name> finished <seconds>
progress_pkg() {
  local name="$1" what="$2" rest=0 n mine=0
  if [ "${what}" = finished ]; then
    hist_set "pkg.${name}" "$3"
    PKG_SECS=$((PKG_SECS + $3))
  fi
  [ -n "${STEAMLING_PROGRESS_FILE:-}" ] || return 0
  if [ "${what}" = started ]; then
    PKG_STARTED=$((PKG_STARTED + 1))
    [ "${PKG_STARTED}" -le "${PKG_TOTAL}" ] || PKG_TOTAL="${PKG_STARTED}"
    read -r mine _ < <(pkg_estimate "${name}" native)
    [ -z "${PKG_LEFT[${name}]:-}" ] || { mine="${PKG_LEFT[${name}]}"; unset "PKG_LEFT[${name}]"; }
  fi
  for n in "${!PKG_LEFT[@]}"; do rest=$((rest + PKG_LEFT[${n}])); done
  if [ "${what}" = started ]; then
    progress_set P_DETAIL "compiling ${name} (${PKG_STARTED} of ${PKG_TOTAL} to compile)" \
      P_STEP_END "$(( $(now_s) + mine + rest ))" P_PKG_SECS "${PKG_SECS}"
  else
    progress_set P_DETAIL "built ${name} in $(fmt_dur "$3")" \
      P_STEP_END "$(( $(now_s) + rest ))" P_PKG_SECS "${PKG_SECS}"
  fi
}

# Does the wanted (pinned) base leave every package installed in the chroot as it is? Its
# packages, makedepends included, are what our binaries were linked against, so if none of
# them changes version and none goes away, what the chroot built is as good on the new base.
base_keeps_chroot() {  # <the chroot's base id>
  [ -n "${STEAMLING_BASE_SNAPSHOT}" ] && [ -n "$1" ] && [ "$1" != live ] || return 1
  local ours moved="" gone="" ok=0 db
  render_base_pacman_conf "${BROOT}/etc/pacman.conf"
  chroot_mount "${BROOT}"
  if chroot "${BROOT}" pacman -Sy --noconfirm >/dev/null 2>&1; then
    # pacman -Sl marks an installed package "[installed: <its version>]" when the repo has another
    moved="$(chroot "${BROOT}" pacman -Sl 2>/dev/null | grep -F '[installed: ' || true)"
    # installed but in no repo: fine for our own packages (makedepends from the local repos)
    ours="$(for db in "${LOCALREPO}/${REPO_DB}" "${LOCALREPO_SHARED}/${SHARED_REPO_DB}"; do
              [ -f "${db}" ] && bsdtar -tf "${db}" 2>/dev/null; done | sed -n 's|^\([^/]*\)/$|\1|p' | sed 's/-[^-]*-[^-]*$//')"
    gone="$(chroot "${BROOT}" pacman -Qmq 2>/dev/null | grep -vxF -f <(printf '%s\n' "${ours}" | sed '/^$/d') || true)"
    [ -z "${moved}" ] && [ -z "${gone}" ] && ok=1
  fi
  chroot_umount "${BROOT}"
  [ "${ok}" = 1 ] || [ -z "${moved}${gone}" ] || log "base ${STEAMLING_BASE_SNAPSHOT} changes $(printf '%s\n' "${moved}" "${gone}" | sed '/^$/d' | wc -l) of this chroot's packages"
  [ "${ok}" = 1 ]
}

setup_chroot() {
  # Base fingerprint: the chroot is built FROM a base (pinned snapshot id, or
  # "live" ALARM) and must be recreated when the pin changes — an old-base chroot
  # stamps binaries with sonames the new base no longer has.
  local want_base="${STEAMLING_BASE_SNAPSHOT:-live}" have_base
  have_base="$(cat "${BROOT}/.base-snapshot" 2>/dev/null || true)"
  if [ -x "${BROOT}/usr/bin/makepkg" ]; then
    # adopt pre-stamp chroots as live-based (the -Syu below converges them)
    if [ -z "${have_base}" ] && [ -z "${STEAMLING_BASE_SNAPSHOT}" ]; then
      printf 'live\n' > "${BROOT}/.base-snapshot"; have_base=live
    fi
    # make extend-base gives the base a new id (20261121 -> 20261121.1) but only adds packages,
    # so a chroot on the old id can already be exactly on the new one. Throwing it away, and
    # everything built in it, rebuilt every package for nothing.
    if [ "${have_base}" != "${want_base}" ] && base_keeps_chroot "${have_base}"; then
      log "base ${want_base} changes nothing this chroot has from ${have_base}: keeping the chroot and the packages it built"
      mkdir -p "${BUILT_BASE_DIR}"
      { printf '%s\n' "${have_base}"; cat "$(base_compat_file "${have_base}")" 2>/dev/null; } \
        >> "$(base_compat_file "${want_base}")"
      sort -u -o "$(base_compat_file "${want_base}")" "$(base_compat_file "${want_base}")"
      _progress_own "${BUILT_BASE_DIR}" "$(base_compat_file "${want_base}")"
      printf '%s\n' "${want_base}" > "${BROOT}/.base-snapshot"; have_base="${want_base}"
    fi
    if [ "${have_base}" != "${want_base}" ]; then
      log "build chroot base is '${have_base:-unknown}', want '${want_base}' — recreating"
      # What this chroot built so far was built against its base: record that before the stamp
      # goes, so those packages rebuild against the new one instead of being reused.
      if [ -n "${have_base}" ]; then
        local r f fs
        for r in "${LOCALREPO}" "${LOCALREPO_SHARED}"; do
          fs=()
          for f in "${r}"/*.pkg.tar.*; do
            case "${f}" in *.sig|*.part) continue ;; esac
            [ -f "${f}" ] && [ ! -e "$(built_base_file "${r}" "${f}")" ] && fs+=("${f}")
          done
          [ "${#fs[@]}" -eq 0 ] || stamp_built_base "${r}" "${have_base}" "${fs[@]}"
        done
      fi
      wipe_chroot
    fi
  fi

  if [ -x "${BROOT}/usr/bin/makepkg" ]; then
    log "reusing build chroot: ${BROOT}"
    # Re-render drops the [steamling] stanza; it is re-appended below, AFTER the
    # -Syu — its file:///localrepo isn't bind-mounted until main(), and pacman
    # dies on a configured repo with no DB.
    render_base_pacman_conf "${BROOT}/etc/pacman.conf"
    # Converge the reused chroot to the configured base. Without this the chroot
    # is frozen at its creation date and LAGS devices (a user's -Syu gets a new
    # soname our binaries were never linked against). Pinned base: no-op.
    chroot_mount "${BROOT}"
    # A PINNED base is frozen, so a chroot already stamped with that pin cannot be stale
    # and a failed -Syu just means offline. On live/unpinned bases the drift is real, and
    # building against a chroot that missed it is exactly what this guard exists to stop.
    if ! chroot "${BROOT}" pacman "$(base_sync_flags)" --noconfirm; then
      if [ -n "${STEAMLING_BASE_SNAPSHOT}" ] && [ "${have_base}" = "${want_base}" ]; then
        warn "chroot -Syu failed, but the base is pinned to ${want_base} and the chroot already matches it — continuing (frozen base cannot have moved)"
      else
        die "chroot base upgrade failed — refusing to build against a stale base (network down? re-run when reachable)"
      fi
    fi
    chroot_umount "${BROOT}"
  else
    fetch_alarm_tarball
    log "creating build chroot -> ${BROOT} (one-time; ~1.5 GB with base-devel)"
    wipe_chroot; mkdir -p "${BROOT}"
    if have bsdtar; then bsdtar -xpf "${TARBALL}" -C "${BROOT}"
    else tar -xpf "${TARBALL}" -C "${BROOT}" --numeric-owner; fi
    maybe_install_qemu "${BROOT}"
    render_base_pacman_conf "${BROOT}/etc/pacman.conf"
    chroot_mount "${BROOT}"
    chroot "${BROOT}" pacman-key --init
    chroot "${BROOT}" pacman-key --populate archlinuxarm
    # same keyring-first step as build-image.sh's configure_keyring
    chroot "${BROOT}" pacman -Sy --noconfirm --needed archlinuxarm-keyring
    chroot "${BROOT}" pacman-key --populate archlinuxarm
    chroot "${BROOT}" pacman "$(base_sync_flags)" --noconfirm --needed base-devel sudo
    chroot_umount "${BROOT}"
    printf '%s\n' "${want_base}" > "${BROOT}/.base-snapshot"
  fi

  # Idempotent: ensure the 'builder' user, sudo, and passwordless sudoers exist — this
  # also repairs chroots created by older versions of this script (which had no sudo),
  # so `makepkg -s` (deps installed via `sudo pacman` as builder) works without a rebuild.
  chroot "${BROOT}" id builder >/dev/null 2>&1 || chroot "${BROOT}" useradd -m builder
  if [ ! -x "${BROOT}/usr/bin/sudo" ]; then
    chroot_mount "${BROOT}"
    chroot "${BROOT}" pacman -Sy --noconfirm --needed sudo
    chroot_umount "${BROOT}"
  fi
  printf 'builder ALL=(ALL) NOPASSWD: ALL\n' > "${BROOT}/etc/sudoers.d/builder"
  chmod 0440 "${BROOT}/etc/sudoers.d/builder"

  # ccache: every build starts from a fresh srcdir, so without it a pkgrel bump or a one-line
  # patch recompiles all of mesa or Cemu, under qemu on an x86 host. The cache lives outside the
  # chroot (PKG_CCACHE_DIR, bind-mounted in main) so a chroot rebuilt for a new base keeps it;
  # ccache's own compiler check drops entries a new gcc would compile differently. A PKGBUILD
  # that misbehaves under it opts out with options=('!ccache').
  local buildenv='!ccache'
  if [ "${STEAMLING_CCACHE}" != off ]; then
    if [ ! -x "${BROOT}/usr/bin/ccache" ]; then
      chroot_mount "${BROOT}"
      # A pinned base only installs what its snapshot holds, and a snapshot only holds what some
      # build installed. Ask first so a missing ccache is one line, not a pacman error.
      if chroot "${BROOT}" pacman -Sp ccache >/dev/null 2>&1; then
        chroot "${BROOT}" pacman -S --noconfirm --needed ccache \
          || warn "could not install ccache in the build chroot; building without it"
      else
        log "ccache: not in base ${STEAMLING_BASE_SNAPSHOT:-live}; building without it (a snapshot taken after a live-base build carries it)"
      fi
      chroot_umount "${BROOT}"
    fi
    [ -x "${BROOT}/usr/bin/ccache" ] && buildenv=ccache
  fi

  # ALARM's makepkg.conf packs with single-threaded xz and leaves MAKEFLAGS unset: under qemu the
  # xz pass outlasts most compiles (fex-rootfs carries a 1.1 GB squashfs) and make-based packages
  # build on one core. makepkg's zstd command is already multi-threaded (-T0).
  install -d "${BROOT}/etc/makepkg.conf.d"
  printf '%s\n' "PKGEXT='.pkg.tar.zst'" 'MAKEFLAGS="-j$(nproc)"' \
    "BUILDENV=(!distcc color ${buildenv} check !sign)" \
    "export CCACHE_DIR=/build/ccache CCACHE_MAXSIZE=${STEAMLING_CCACHE_SIZE} CCACHE_COMPRESS=1" \
    > "${BROOT}/etc/makepkg.conf.d/steamling.conf"

  # Local [steamling] repo so a package can depend on another locally-built one. Points at
  # the bind-mounted /localrepo. SigLevel Never, same reason as build-image.sh's
  # append_local_repo: a signed localrepo db makes Optional TrustAll die on the unknown
  # key when makepkg -s installs a locally-built dep. The sed branch repairs REUSED
  # chroots that were created with the old stanza.
  if ! grep -q '^\[steamling\]' "${BROOT}/etc/pacman.conf"; then
    printf '\n[steamling]\nSigLevel = Never\nServer = file:///localrepo\n' \
      >> "${BROOT}/etc/pacman.conf"
  else
    sed -i '/^\[steamling\]/,/^\[/{s/^SigLevel = Optional TrustAll$/SigLevel = Never/;}' \
      "${BROOT}/etc/pacman.conf"
  fi
  # Same for [steamling-shared]: makepkg -s must resolve shared siblings too
  # (e.g. cemu -> wxwidgets-steamling).
  if ! grep -q '^\[steamling-shared\]' "${BROOT}/etc/pacman.conf"; then
    printf '\n[steamling-shared]\nSigLevel = Never\nServer = file:///localrepo-shared\n' \
      >> "${BROOT}/etc/pacman.conf"
  fi
}

build_one() {
  local pkgdir="$1" force="${2:-0}" name env; name="$(pkg_name "${pkgdir}")"; env="$(pkg_env "${pkgdir}")"
  local repo_dir repo_db repo_mount
  repo_dir="$(pkg_repo_dir "${pkgdir}")"
  repo_db="$(pkg_repo_db "${pkgdir}")"
  repo_mount="$(pkg_repo_mount "${pkgdir}")"
  # STEAMLING_KEEP_PKGS="a b": ship what localrepo already has for these instead of rebuilding,
  # for when a package's sources can't be downloaded (archive.archlinux.org down) and every
  # attempt would sit waiting on it. PKG= still rebuilds them.
  if [ "${force}" -eq 0 ] && [[ " ${STEAMLING_KEEP_PKGS:-} " == *" ${name} "* ]]; then
    local kept
    kept="$(ls -1 "${repo_dir}/${name}"-[0-9]*.pkg.tar.* "${repo_dir}/${name}"-*:*.pkg.tar.* 2>/dev/null \
      | grep -v '\.sig$' | head -1)"
    if [ -n "${kept}" ]; then
      warn "keep: ${name} not rebuilt (STEAMLING_KEEP_PKGS), $(basename "${kept}") ships as it is"
      return 0
    fi
    warn "${name} is in STEAMLING_KEEP_PKGS but localrepo has no copy of it, so it builds anyway"
  fi
  rm -rf "${BROOT}/build/${name}"
  mkdir -p "${BROOT}/build"
  cp -r "${pkgdir}" "${BROOT}/build/${name}"
  chroot "${BROOT}" chown -R builder:builder "/build/${name}"
  # Incremental skip: if every artifact this PKGBUILD would produce (per `makepkg
  # --packagelist`: name-[epoch:]ver-rel-arch, split siblings included) is already in the
  # localrepo AND newer than every file in the package dir, there is nothing to do — so a
  # re-run of `make build` doesn't recompile mesa/gamescope/the world. Editing any file in
  # the package dir (patch, script, PKGBUILD) triggers a rebuild without needing a pkgrel
  # bump. Force paths: `make packages PKG=<name>` always rebuilds the named packages;
  # STEAMLING_FORCE_REBUILD=1 rebuilds everything. The kernel package also rebuilds whenever
  # `make kernel` produced a newer Image than the packaged one.
  if [ "${force}" -eq 0 ]; then
    local uptodate=1 nlist=0 p f
    while IFS= read -r p; do
      nlist=$((nlist+1))
      # Matched without the extension: seeded and older builds are .xz, new ones .zst.
      f="$(artifact_file "${repo_dir}" "$(basename "${p%.pkg.tar.*}")")" || f=""
      [ -n "${f}" ] && artifact_current "${f}" "${pkgdir}" "${name}" || { uptodate=0; break; }
      if ! artifact_on_base "${repo_dir}" "${f}"; then
        log "${name}: built against base $(cat "$(built_base_file "${repo_dir}" "${f}")" 2>/dev/null || echo '?'), this build uses ${STEAMLING_BASE_SNAPSHOT:-live}; rebuilding"
        uptodate=0; break
      fi
    done < <(chroot "${BROOT}" runuser -u builder -- \
               bash -lc "cd /build/${name} && LC_ALL=C ${env} makepkg --packagelist" 2>/dev/null)
    if [ "${nlist}" -gt 0 ] && [ "${uptodate}" -eq 1 ]; then
      log "skip: ${name} (already in localrepo, sources unchanged — force with PKG=${name})"
      return 0
    fi
  fi
  log "makepkg: ${name}"
  local t0; t0="$(now_s)"
  progress_pkg "${name}" started
  # Refresh the chroot's sync DBs (incl. [steamling], so makepkg -s sees siblings built
  # earlier this run) — only here, when actually building; skipped packages must not
  # each pay a network DB refresh.
  chroot "${BROOT}" pacman -Sy --noconfirm >/dev/null 2>&1 || true
  # The kernel package is THIN: it doesn't compile the kernel (no makepkg/toolchain in the
  # chroot for that), it just packages `make kernel`'s output. Stage ${KERNEL_BUILD_DIR}/out
  # into the package build dir as ./staged so its package() can lay it out as /boot +
  # /usr/lib/modules.
  if [ "${name}" = "${KERNEL_PKG}" ]; then
    local kout="${KERNEL_BUILD_DIR}/out"
    if [ ! -f "${kout}/Image" ] || [ ! -f "${kout}/kernelrelease" ]; then
      warn "${name}: no kernel build at ${kout} — run 'make kernel' first; skipping"
      return 1
    fi
    # SoC marker sanity: catches a copied/renamed out/ dir from another SoC
    if [ -f "${kout}/soc" ] && [ "$(cat "${kout}/soc")" != "${SOC}" ]; then
      warn "${name}: ${kout} was built for SOC=$(cat "${kout}/soc"), not ${SOC} — run 'make kernel DEVICE=${DEVICE}' first; skipping"
      return 1
    fi
    cp -a "${kout}" "${BROOT}/build/${name}/staged"
  fi
  # The cmdline is written once, in the profile: the BSP installs it for the on-device boot
  # image rebuild.
  if [ "${name}" = "${DEVICE_BSP_PKG}" ]; then
    mkdir -p "${BROOT}/build/${name}/staged"
    printf '%s\n' "${KERNEL_CMDLINE}" > "${BROOT}/build/${name}/staged/kernel-cmdline"
  fi
  if [ "${name}" = "${DEVICE_BSP_PKG}" ]; then
    BOOTLOADER="${BOOTLOADER}" SD_FAT_LABEL="${SD_FAT_LABEL}" ROOT_LABEL="${ROOT_LABEL}" \
      "${STEAMLING_ROOT}/scripts/render-bsp.sh" "${pkgdir}/boards" "${BROOT}/build/${name}/staged"
  fi
  # Persistent source cache: SRCDEST lives OUTSIDE the per-package build dir (which is wiped
  # every run), so makepkg downloads each source ONCE and reuses it. File sources (e.g.
  # fex-emu's pinned x86 sysroot .pkg.tar.zst, ~70 MB) are kept by name; the git source becomes
  # a cached clone that only `git fetch`es deltas instead of re-cloning 100k+ objects each build.
  mkdir -p "${BROOT}/build/srccache"
  chroot "${BROOT}" chown -R builder:builder "/build/${name}"
  chroot "${BROOT}" chown builder:builder /build/srccache
  # Files only the Arch Linux Archive still has come from Steamling's own copies first (make
  # publish-sources), so the archive being down can't stall a build. A copy only goes into the
  # cache when its sha256 matches the PKGBUILD's; anything else is left to makepkg as usual.
  if [ -n "${STEAMLING_SOURCES_URL}" ]; then
    local sn ssum sf
    while read -r sn ssum; do
      sf="${BROOT}/build/srccache/${sn}"
      [ -n "${sn}" ] && [ ! -f "${sf}" ] || continue
      if curl -fsSL --retry 2 --connect-timeout 15 -o "${sf}.part" "${STEAMLING_SOURCES_URL}/$(base_file_name "${sn}")" \
          && [ "$(sha256sum "${sf}.part" | cut -d' ' -f1)" = "${ssum}" ]; then
        mv -f "${sf}.part" "${sf}"
        chroot "${BROOT}" chown builder:builder "/build/srccache/${sn}"
        log "${name}: ${sn} from Steamling's own copy"
      fi
      rm -f "${sf}.part"
    done < <(archive_sources "${pkgdir}")
  fi
  # makepkg refuses to run as root; build as the 'builder' user.
  # -s syncs makedepends (gamescope needs many). Device packages (devices/*/packages/*:
  # BSPs + metapackages) are pure file-drop/meta packages built with --nodeps instead:
  # with -s makepkg would install their RUNTIME dependency closure into the build chroot
  # (the kernel package, the Steam stack, fex-rootfs) just to lay out a few files. Their
  # depends= still ships in the .pkg metadata; -d only skips build-time resolution. A
  # ./nodeps marker opts in other packages whose runtime deps would drag a layer in.
  # Per-SoC tuning (devices/<soc>/tuning.conf via lib.sh) rides the makepkg environment
  # (pkg_env): the tuned PKGBUILDs read STEAMLING_TUNE_CFLAGS/STEAMLING_FEX_TUNE_CPU
  # (falling back to their sm8550 strings when unset, e.g. standalone makepkg).
  local mkflags="-s"
  case "${pkgdir}" in */devices/*/packages/*) mkflags="-d" ;; esac
  [ -f "${pkgdir}/nodeps" ] && mkflags="-d"
  if ! chroot "${BROOT}" runuser -u builder -- \
      bash -lc "cd /build/${name} && LC_ALL=C SRCDEST=/build/srccache ${env} makepkg ${mkflags} -f --noconfirm --nocheck --skippgpcheck"; then
    warn "makepkg failed for ${name} — keeping any previous build in ${repo_dir##*/}"
    return 1
  fi
  # Collect what makepkg ACTUALLY produced via `makepkg --packagelist`: a split PKGBUILD
  # (packages/soc/mesa -> mesa + vulkan-freedreno) emits sibling packages a "${name}-*" glob
  # misses (only the mesa half would reach localrepo), while a bare *.pkg.tar.*
  # sweep would grab .pkg.tar.* files that are makepkg *sources* symlinked into the build
  # dir (e.g. fex-emu's pinned x86 sysroot pkgs). --packagelist names exactly the built
  # artifacts, epoch and all.
  local built_pkgs=() p
  while IFS= read -r p; do
    p="${BROOT}/build/${name}/$(basename "${p}")"
    [ -e "${p}" ] && built_pkgs+=("${p}")
  done < <(chroot "${BROOT}" runuser -u builder -- \
             bash -lc "cd /build/${name} && LC_ALL=C ${env} makepkg --packagelist" 2>/dev/null)
  if [ "${#built_pkgs[@]}" -eq 0 ]; then
    warn "no .pkg.tar.* produced for ${name} — keeping any previous build"
    return 1
  fi
  # ONLY NOW touch the repo. Removing the previous version(s) and publishing the new one happens
  # AFTER a confirmed successful build, so a failed/transient rebuild never wipes a known-good
  # package (build-to-temp-then-swap). The rm also clears stale dupes that would otherwise break
  # `pacman -U pkg-*.tar` with "duplicate target". (rm before cp: the new file's own epoch'd name
  # matches the *:* pattern, so cp-then-rm would delete what we just copied.) Clear per PRODUCED
  # package name — split siblings each have their own previous versions.
  local base
  for p in "${built_pkgs[@]}"; do
    base="$(basename "${p}")"
    base="${base%-*}"; base="${base%-*}"; base="${base%-*}"  # strip -<ver>-<rel>-<arch>.pkg.tar.*
    rm -f "${repo_dir}/${base}"-[0-9]*.pkg.tar.* "${repo_dir}/${base}"-*:*.pkg.tar.* 2>/dev/null || true
  done
  cp "${built_pkgs[@]}" "${repo_dir}/"
  stamp_built_base "${repo_dir}" "${STEAMLING_BASE_SNAPSHOT:-live}" "${built_pkgs[@]}"
  # Register exactly the artifacts just built (NOT *.pkg.tar.* — re-adding the whole repo
  # for every package spammed 'entry already existed' x N^2). LC_ALL=C: the build chroot
  # has no generated locales, and bsdtar warns on every tar op otherwise.
  local addlist=""
  for p in "${built_pkgs[@]}"; do addlist+=" $(basename "${p}")"; done
  chroot "${BROOT}" bash -lc "cd ${repo_mount} && LC_ALL=C repo-add -q ${repo_db}${addlist}" || return 1
  progress_pkg "${name}" finished "$(( $(now_s) - t0 ))"
}

main() {
  # Optional args = package names to build (subset, always rebuilt); no args = build
  # everything, skipping packages already up-to-date in the localrepo (see build_one).
  # e.g. `make packages PKG="inputplumber steamling-bsp-sm8550"` to force just those two.
  local want=("$@")
  mkdir -p "${LOCALREPO}" "${LOCALREPO_SHARED}"
  [ "${#want[@]}" -gt 0 ] || progress_pkgs_init
  progress_detail "preparing the build chroot"
  setup_chroot
  progress_detail "checking which packages are current"

  chroot_mount "${BROOT}"
  # Keep both local repos bind-mounted throughout so makepkg -s can resolve inter-package
  # local deps (e.g. cemu -> wxwidgets-steamling) from [steamling]/[steamling-shared] as we go.
  mkdir -p "${BROOT}/localrepo" "${BROOT}/localrepo-shared"
  mount --bind "${LOCALREPO}" "${BROOT}/localrepo"
  mount --bind "${LOCALREPO_SHARED}" "${BROOT}/localrepo-shared"
  mkdir -p "${PKG_CCACHE_DIR}" "${BROOT}/build/ccache"
  mount --bind "${PKG_CCACHE_DIR}" "${BROOT}/build/ccache"
  chroot "${BROOT}" chown builder:builder /build/ccache
  [ ! -x "${BROOT}/usr/bin/ccache" ] || chroot "${BROOT}" env CCACHE_DIR=/build/ccache ccache --zero-stats >/dev/null 2>&1 || true
  # Initialize both dbs so the repos are valid even on the first/partial run
  # (one full re-add; per-package registration during the run adds only new artifacts).
  local rmount rdb
  for rmount in /localrepo /localrepo-shared; do
    rdb="${REPO_DB}"; [ "${rmount}" = "/localrepo-shared" ] && rdb="${SHARED_REPO_DB}"
    # A lock left by an interrupted run makes repo-add refuse the db. Only one build runs per
    # checkout (build-all.sh), so a lock present now is stale.
    rm -f "${BROOT}${rmount}/${rdb}.lck"
    if ls "${BROOT}${rmount}"/*.pkg.tar.* >/dev/null 2>&1; then
      # Captured, not discarded: a failure here used to end the build with no message at all.
      local out
      if ! out="$(chroot "${BROOT}" bash -lc "cd ${rmount} && LC_ALL=C repo-add -q ${rdb} \$(ls *.pkg.tar.* | grep -v '\.sig\$')" 2>&1)"; then
        printf '%s\n' "${out}" | tail -n 20 >&2
        die "repo-add could not index ${rmount#/} (${rdb}); its output is above"
      fi
    else
      chroot "${BROOT}" bash -lc "cd ${rmount} && tar -czf ${rdb} -T /dev/null && ln -sf ${rdb} ${rdb%.tar.gz}"
    fi
  done

  # Build a package (build_one registers its artifacts in its repo so later packages
  # see them; the pacman -Sy refresh happens inside build_one, only for real builds).
  try_build() {
    if build_one "$1" "${2:-0}"; then
      built=$((built+1))
      return 0
    fi
    return 1
  }

  local built=0 name force devdir devsoc pkgsocs
  local -a failed=()
  # Per-SoC and device packages build only into the CURRENT SoC's repo: device packages by
  # their profile's SOC, packages/soc by ./socs. PKG= names and STEAMLING_FORCE_REBUILD=1 force
  # past the up-to-date skip.
  for pkgdir in "${PACKAGES_DIR}"/shared/*/ "${PACKAGES_DIR}"/soc/*/ "${STEAMLING_ROOT}"/devices/*/packages/*/; do
    [ -f "${pkgdir}/PKGBUILD" ] || continue
    name="$(pkg_name "${pkgdir}")"
    # Opt-in packages (lib.sh pkg_opted_out) build when their switch is on or PKG= names them.
    if pkg_opted_out "${pkgdir}"; then
      case " ${want[*]} " in *" ${name} "*) ;; *) continue ;; esac
    fi
    case "${pkgdir}" in */devices/*/packages/*)
      devdir="$(dirname "$(dirname "${pkgdir%/}")")"
      devsoc="$(profile_get "${devdir}" SOC)"
      [ "${devsoc}" = "${SOC}" ] || continue
    ;; esac
    case "${pkgdir}" in
      */packages/soc/*)
        [ -f "${pkgdir}/socs" ] || die "${name}: packages/soc/ package with no socs file: declare its SoC(s), or all, on one space-separated line"
        read -r pkgsocs < "${pkgdir}/socs" || true   # a 0-byte file fails read; the next line names it
        [ -n "${pkgsocs}" ] || die "${name}: empty socs file"
        case " ${pkgsocs} " in " all "|*" ${SOC} "*) ;; *) continue ;; esac ;;
    esac
    force=0
    [ "${STEAMLING_FORCE_REBUILD:-0}" = "1" ] && force=1
    if [ "${#want[@]}" -gt 0 ]; then
      case " ${want[*]} " in *" ${name} "*) force=1 ;; *) continue ;; esac
    fi
    PKG_CHECKED=$((PKG_CHECKED + 1))
    [ "${PKG_DIRS}" -lt "${PKG_CHECKED}" ] || progress_detail "checking ${name} (package ${PKG_CHECKED} of ${PKG_DIRS})"
    try_build "${pkgdir}" "${force}" || failed+=("${pkgdir}")
  done

  # Dependency order != alphabetical: a package can depend on a sibling the glob builds LATER,
  # so its first `makepkg -s` aborts with "target not found". Retry failures: once a dep lands
  # in its repo the dependent builds. Loop until a full pass makes no progress (then they're
  # real failures).
  while [ "${#failed[@]}" -gt 0 ]; do
    local -a retry=("${failed[@]}"); failed=(); local progress=0
    for pkgdir in "${retry[@]}"; do
      if try_build "${pkgdir}"; then progress=1; else failed+=("${pkgdir}"); fi
    done
    [ "${progress}" -eq 1 ] || break
  done
  # --- failure summary: surface the SILENT danger. A failed rebuild that left an OLDER build in
  # localrepo gets installed by build-image with no error, so a stale package ships. Split the
  # failures into "stale artifact still present" (dangerous, loud) vs "no artifact" (build-image
  # errors at install, not silent).
  if [ "${#failed[@]}" -gt 0 ]; then
    local -a stale=() gone=() fnames=()
    local fp fname base p af had line frepo
    for fp in "${failed[@]}"; do
      fname="$(pkg_name "${fp}")"; had=0; fnames+=("${fname}")
      frepo="$(pkg_repo_dir "${fp}")"
      # artifact base name(s) this PKGBUILD produces (split pkgs -> several); --packagelist only
      # reads the PKGBUILD so it works even though the build failed.
      while IFS= read -r p; do
        [ -n "${p}" ] || continue
        base="$(basename "${p}")"; base="${base%-*}"; base="${base%-*}"; base="${base%-*}"
        for af in "${frepo}/${base}"-[0-9]*.pkg.tar.* "${frepo}/${base}"-*:*.pkg.tar.*; do
          [ -e "${af}" ] || continue
          stale+=("${base}  (localrepo still has $(basename "${af}"))"); had=1
        done
      done < <(chroot "${BROOT}" runuser -u builder -- \
                 bash -lc "cd /build/${fname} 2>/dev/null && LC_ALL=C $(pkg_env "${fp}") makepkg --packagelist" 2>/dev/null)
      [ "${had}" -eq 0 ] && gone+=("${fname}")
    done
    echo >&2
    warn "PACKAGE BUILD FAILURES (${#failed[@]}): ${fnames[*]}"
    if [ "${#stale[@]}" -gt 0 ]; then
      warn "  STALE ARTIFACT WILL SHIP: the rebuild failed but an OLD version stays in localrepo,"
      warn "  so 'make build' installs the stale one with no error. Rebuild before building an image:"
      while IFS= read -r line; do warn "    - ${line}"; done < <(printf '%s\n' "${stale[@]}" | sort -u)
    fi
    [ "${#gone[@]}" -gt 0 ] && warn "  no artifact in localrepo (build-image errors at install, not silent): ${gone[*]}"
  fi

  if [ -x "${BROOT}/usr/bin/ccache" ] && [ "${built}" -gt 0 ]; then
    log "ccache this run: $(chroot "${BROOT}" env CCACHE_DIR=/build/ccache ccache --show-stats 2>/dev/null \
      | grep -m1 -iE '^ *(cacheable calls|hits):' | sed 's/^ *//')"
  fi
  umount "${BROOT}/build/ccache"
  umount "${BROOT}/localrepo"
  umount "${BROOT}/localrepo-shared"
  chroot_umount "${BROOT}"
  trap - EXIT

  [ "${built}" -gt 0 ] || die "no packages built"
  ok "local repos ready -> ${LOCALREPO} + ${LOCALREPO_SHARED}"
  # An empty repo leaves its glob unmatched and ls exits 2, which pipefail would turn into a
  # failed build (and abort `make build`) after every package built fine.
  { ls -1 "${LOCALREPO}"/*.pkg.tar.* "${LOCALREPO_SHARED}"/*.pkg.tar.* 2>/dev/null || true; } | sed 's#.*/#  #'
}

main "$@"
