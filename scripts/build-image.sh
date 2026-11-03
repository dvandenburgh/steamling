#!/usr/bin/env bash
# build-image.sh — build the complete steamling ROOTFS (make build).
#
# Pipeline:
#   bootstrap -> configure pacman -> install packages (base + session lists) -> local steamling
#   packages (incl. the SoC kernel and firmware) -> bake the native Steam client
#
# The output is a finished rootfs at ${ROOTFS_DIR}. Turning that into a flashable image
# (partitioning, boot KERNEL, first-boot config) is a SEPARATE step: scripts/build-sd-image.sh
# (make sd-image).

source "$(dirname "$0")/lib.sh"
need_linux
need_root build
for t in curl tar sed; do need_tool "$t"; done

LOCAL_REPO_DIR="${LOCALREPO_DIR}"                 # per-SoC: build/localrepo/${SOC} (set in lib.sh)
LOCAL_REPO_SHARED_DIR="${LOCALREPO_SHARED_DIR}"   # SoC-neutral: build/localrepo/shared

# ES-DE + the emulators are an opt-in layer Steamling Tools installs, so the image leaves them
# out; =1 bakes them in (and their ALARM deps then need no base-extras.list entry).
STEAMLING_EMULATION="${STEAMLING_EMULATION:-0}"

# Documentation nobody reads on a handheld: package docs, the KDE and GNOME handbooks, gtk-doc.
# NoExtract keeps them out of every install, the image's and every later update's;
# strip_docs clears what the base tarball unpacked before pacman.conf existed. Licenses
# (/usr/share/licenses) and man pages stay.
STEAMLING_NOEXTRACT="${STEAMLING_NOEXTRACT-usr/share/doc/* usr/share/gtk-doc/* usr/share/help/*}"
# The image used to carry a copy of every installed package in /var/cache/pacman/pkg, several GB
# on the card that nothing on the device reads. =1 brings it back (an offline reinstall source).
STEAMLING_IMAGE_PKG_CACHE="${STEAMLING_IMAGE_PKG_CACHE:-0}"

render_pacman_conf() {
  local out="$1"
  log "rendering pacman.conf (base: ${STEAMLING_BASE_SNAPSHOT:-live ALARM})"
  render_base_pacman_conf "${out}"
  [ -z "${STEAMLING_NOEXTRACT}" ] || sed -i "/^\[options\]$/a NoExtract   = ${STEAMLING_NOEXTRACT}" "${out}"
}

strip_docs() {
  local root="$1" d
  [ -n "${STEAMLING_NOEXTRACT}" ] || return 0
  for d in usr/share/doc usr/share/gtk-doc usr/share/help; do
    [ -d "${root}/${d}" ] && find "${root}/${d}" -mindepth 1 -delete
  done
  log "stripped package documentation"
}

# The local repos live on the host; we bind-mount them to /localrepo{,-shared}
# inside the rootfs chroot. Inserted ABOVE the first base repo (not appended):
# unqualified names — the layer metas' depends resolve this way — pick the
# FIRST repo in pacman.conf order, and ours must outrank ALARM, exactly like
# the shipped stanzas.
append_local_repo() {
  local out="$1"
  grep -q '^\[steamling\]' "${out}" && return 0
  log "adding local steamling + steamling-shared repos"
  local anchor="core"
  grep -q '^\[pocknix-base\]' "${out}" && anchor="pocknix-base"
  sed -i "0,/^\[${anchor}\]/s||[steamling]\nSigLevel = Never\nServer = file:///localrepo\n\n[steamling-shared]\nSigLevel = Never\nServer = file:///localrepo-shared\n\n[${anchor}]|" \
    "${out}"
}

# STEAMLING_IMAGE_PKG_CACHE=1: the image keeps each installed package in its own
# /var/cache/pacman/pkg. Hard links into build/cache and build/localrepo make that free on the host.
link_installed_into_cache() {
  local root="$1" dst="$1/var/cache/pacman/pkg" d dir f n=0
  ! mountpoint -q "${dst}" || die "${dst} is still the shared cache's mount point"
  for d in "${root}"/var/lib/pacman/local/*/; do
    d="$(basename "${d}")"
    for dir in "${PKG_CACHE_DIR}" "${LOCAL_REPO_DIR}" "${LOCAL_REPO_SHARED_DIR}"; do
      for f in "${dir}/${d}"-aarch64.pkg.tar.* "${dir}/${d}"-any.pkg.tar.*; do
        [ -f "${f}" ] || continue
        case "${f}" in *.part) continue ;; esac
        ln -f "${f}" "${dst}/" 2>/dev/null || cp -f "${f}" "${dst}/"
        n=$((n + 1))
      done
    done
  done
  log "linked ${n} package files into the image's pacman cache"
}

# fontconfig installs and caches long before any steamling package, so the package's own prune can
# leave an image dirty: re-prune after the last transaction.
prune_fontconfig_compat_links() {
  local root="$1"
  [ -d "${root}/var/cache/fontconfig" ] || return 0
  local n
  n="$(find "${root}/var/cache/fontconfig" -maxdepth 1 -type l -name '*.cache-*' -print -delete 2>/dev/null | wc -l | tr -d ' ')"
  log "pruned ${n} stale-version fontconfig cache links"
}

# Install the local steamling packages into the rootfs: the layer metapackages
# (steamling-core + the three optional layers — their depends= ARE the manifest,
# see packages/shared/steamling-*/PKGBUILD), the SoC kernel (${KERNEL_PKG}), then
# the device metapackage (${DEVICE_META_PKG}) with the per-SoC set.
install_local_packages() {
  local root="$1"
  if [ ! -f "${LOCAL_REPO_DIR}/steamling.db" ] || [ ! -f "${LOCAL_REPO_SHARED_DIR}/steamling-shared.db" ]; then
    warn "no local repos at ${LOCAL_REPO_DIR} + ${LOCAL_REPO_SHARED_DIR} (build-packages.sh didn't run?) — skipping local pkgs"
    return 0
  fi
  log "installing local steamling packages (layer metapackages + ${DEVICE} device set)"
  progress_detail "installing the steamling packages"
  append_local_repo "${root}/etc/pacman.conf"
  mkdir -p "${root}/localrepo" "${root}/localrepo-shared"
  mount --bind "${LOCAL_REPO_DIR}" "${root}/localrepo"
  mount --bind "${LOCAL_REPO_SHARED_DIR}" "${root}/localrepo-shared"
  chroot "${root}" pacman -Sy --noconfirm
  # Same-name replacements FIRST, explicitly qualified: mesa + vulkan-freedreno
  # (our epoch-2 trimmed/tuned freedreno/turnip builds), gamescope (ROCKNIX-
  # patched; vanilla black-screens the rotated panel) and mangohud (Adreno
  # reader, from [steamling-shared]) REPLACE the ALARM copies base.list installed
  # for bootstrap. They are depends of the metas below, but a dep already
  # satisfied by ALARM's installed copy would never be upgraded by a meta
  # install — so force ours here, loudly.
  chroot "${root}" pacman -S --noconfirm --needed \
    steamling/mesa steamling/vulkan-freedreno steamling/gamescope steamling-shared/mangohud
  # The layer metas (STEAMLING_EMULATION=1 adds emulation). Their unqualified depends
  # resolve by repo order: [steamling] + [steamling-shared] sit ABOVE the base repos
  # (append_local_repo), so steamling names resolve to our builds, ALARM names to base.
  local metas=(steamling-core steamling-steam-full steamling-desktop-full)
  if [ "${STEAMLING_EMULATION}" = 1 ]; then metas+=(steamling-emulation-full)
  else log "emulation layer left out (STEAMLING_EMULATION=1 bakes it in)"; fi
  chroot "${root}" pacman -S --noconfirm --needed "${metas[@]/#/steamling-shared/}"
  # GUARD: these local builds MUST come from [steamling], not silently fall back / go missing. gamescope
  # especially: without composite rotation it requests a plane rotation the msm DPU rejects.
  local mesa_ver; mesa_ver="$(chroot "${root}" pacman -Q mesa 2>/dev/null | awk '{print $2}')"
  case "${mesa_ver}" in
    2:*) log "mesa OK: ${mesa_ver} (epoch-2 steamling trimmed build)" ;;
    *) die "mesa resolved to '${mesa_ver}', NOT our epoch-2 [steamling] build — the image would ship ALARM's all-driver mesa. Confirm build/localrepo/mesa-2:*.pkg.tar.* exists AND is in steamling.db ('make packages PKG=mesa'), then re-run." ;;
  esac
  local gs_ver; gs_ver="$(chroot "${root}" pacman -Q gamescope 2>/dev/null | awk '{print $2}')"
  case "${gs_ver}" in
    1:*rocknix*) log "gamescope OK: ${gs_ver} (epoch-1 patched build)" ;;
    *) die "gamescope resolved to '${gs_ver}', NOT our epoch-1 [steamling] rocknix build. Vanilla gamescope can't drive the RP6's rotated panel (no --use-rotation-shader) -> black screen. The install pins steamling/gamescope, so reaching here means [steamling] is missing it: confirm build/localrepo/gamescope-1:*.pkg.tar.* exists AND is registered in steamling.db ('make packages PKG=gamescope' rebuilds + repo-adds it), then re-run." ;;
  esac
  local lp
  for lp in fex-emu fex-rootfs; do
    chroot "${root}" pacman -Q "${lp}" >/dev/null 2>&1 || {
      die "${lp} not installed — its local build wasn't in [steamling]. Build it: 'make packages PKG=${lp}' (fex-rootfs downloads the ~1.1 GB Arch x86 squashfs once), confirm build/localrepo/${lp}-*.pkg.tar.* exists, then re-run."
    }
  done
  # steamling-desktop must come from [steamling-shared] too (its flavour dep pulls in the whole DE).
  chroot "${root}" pacman -Q steamling-desktop >/dev/null 2>&1 || {
    die "steamling-desktop not installed — its local build wasn't in [steamling]. Build it: 'make packages PKG=steamling-desktop', confirm build/localrepo/steamling-desktop-*.pkg.tar.* exists, then re-run."
  }
  # Source-built emulators (SoC-tuned, so [steamling]) are optdepends of steamling-emulation-full: a missing one only
  # drops that system from ES-DE, so warn here rather than fail the whole image.
  local oe
  if [ "${STEAMLING_EMULATION}" = 1 ]; then
    for oe in dolphin-emu azahar cemu; do
      chroot "${root}" pacman -S --noconfirm --needed "steamling/${oe}" 2>/dev/null \
        || warn "optional emulator ${oe} not in [steamling] (build failed/skipped?) — image ships WITHOUT it"
    done
  fi
  # Kernel: swap ALARM's generic linux-aarch64 for our SoC kernel package (Image + modules,
  # built by `make kernel` -> staged into the package). Its own step (not bundled above) so a
  # missing kernel build errors clearly, and the replace is deterministic. `provides=linux`.
  if chroot "${root}" pacman -Si "steamling/${KERNEL_PKG}" >/dev/null 2>&1; then
    chroot "${root}" pacman -Rdd --noconfirm linux-aarch64 2>/dev/null || true
    rm -rf "${root}/boot/initramfs-linux"*.img 2>/dev/null || true
    chroot "${root}" pacman -S --noconfirm "steamling/${KERNEL_PKG}"
    chroot "${root}" pacman -Q "${KERNEL_PKG}" >/dev/null 2>&1 || {
      die "${KERNEL_PKG} failed to install — check the pacman output above."
    }
    log "kernel OK: $(chroot "${root}" pacman -Q "${KERNEL_PKG}")"
  else
    die "${KERNEL_PKG} not in [steamling] — run 'make kernel' first (build-packages.sh stages build/kernel/out into the package), then re-run. Without it the rootfs has no matching modules for the booted kernel."
  fi
  # Device selection LAST: the device metapackage pins the device identity and pulls the BSP +
  # the kernel package (already present).
  chroot "${root}" pacman -S --noconfirm --needed "steamling/${DEVICE_META_PKG}"
  chroot "${root}" pacman -Q "${DEVICE_BSP_PKG}" >/dev/null 2>&1 || {
    die "${DEVICE_BSP_PKG} not installed — ${DEVICE_META_PKG} should have pulled it. Check its depends= and 'make packages'."
  }
  log "device OK: $(chroot "${root}" pacman -Q "${DEVICE_META_PKG}" 2>/dev/null || echo "${DEVICE}")"
  umount "${root}/localrepo"
  umount "${root}/localrepo-shared"
  rmdir "${root}/localrepo" "${root}/localrepo-shared" 2>/dev/null || true
  # NB the build-time sync dbs must NOT be dropped here: make snapshot harvests
  # its name->filename/sha mapping from this rootfs's dbs. build-sd-image.sh
  # deletes them from the IMAGE copy instead (they must not ship: see there).
  # Drop the build-only stanzas (their file:///localrepo* bind mounts don't exist on
  # the device). With STEAMLING_REPO_URL set, re-add stanzas pointing at the PUBLISHED
  # repos, inserted ABOVE [core]: `pacman -S
  # <name>` picks the FIRST repo that carries the name, so steamling must outrank ALARM
  # for our same-name packages (mesa, gamescope, ...). Without it the image is reflash-only.
  # Live ALARM with no repo of ours: [extra] carries newer same-name packages (mesa, gamescope...)
  # and the first -Syu would swap our builds for them. They can only change by reflashing anyway,
  # so hold each one ALARM also has. (Read before the stanzas go: -Sl needs the repo configured.)
  local held=""
  if [ -z "${STEAMLING_REPO_URL}" ] && [ -z "${STEAMLING_BASE_SNAPSHOT}" ]; then
    held="$(LC_ALL=C comm -12 \
              <(chroot "${root}" pacman -Slq steamling steamling-shared 2>/dev/null | LC_ALL=C sort -u) \
              <(chroot "${root}" pacman -Slq core extra alarm aur 2>/dev/null | LC_ALL=C sort -u) \
            | LC_ALL=C comm -12 - <(chroot "${root}" pacman -Qq | LC_ALL=C sort) | tr '\n' ' ')"
  fi
  sed -i '/^\[steamling\]/,+2d;/^\[steamling-shared\]/,+2d' "${root}/etc/pacman.conf"
  if [ -n "${held// /}" ]; then
    sed -i "/^\[options\]$/a IgnorePkg   = ${held% }" "${root}/etc/pacman.conf"
    log "live base, no package repo: holding our builds of ${held% } against ALARM's"
  fi
  # Published repos: STEAMLING_REPO_URL is the BASE url. [steamling] is per-SoC
  # (<base>/<soc> — tuned packages share pkgnames across SoCs with different
  # binaries, so those trees must not mix); [steamling-shared] (<base>/shared) is
  # one tree for all SoCs. Order matters: per-SoC FIRST so a tuned package could
  # never be shadowed by a same-name shared one.
  if [ -n "${STEAMLING_REPO_URL}" ]; then
    log "shipping [steamling] -> ${STEAMLING_REPO_URL}/${SOC} + [steamling-shared] -> ${STEAMLING_REPO_URL}/shared (SigLevel ${STEAMLING_REPO_SIGLEVEL})"
    # anchor = the first base repo: [core] on a live-ALARM conf, [pocknix-base] on a
    # pinned one (which has no [core] at all, so anchoring on [core] would silently no-op)
    local anchor="core"
    grep -q '^\[pocknix-base\]' "${root}/etc/pacman.conf" && anchor="pocknix-base"
    sed -i "0,/^\[${anchor}\]/s||[steamling]\nSigLevel = ${STEAMLING_REPO_SIGLEVEL}\nServer = ${STEAMLING_REPO_URL}/${SOC}\n\n[steamling-shared]\nSigLevel = ${STEAMLING_REPO_SIGLEVEL}\nServer = ${STEAMLING_REPO_URL}/shared\n\n[${anchor}]|" \
      "${root}/etc/pacman.conf"
    # Trust the repo key out of the box: bake the exported public key + lsign it, so a
    # fresh image can `pacman -Syu` without a manual pacman-key dance.
    if [ -n "${STEAMLING_REPO_PUBKEY}" ]; then
      [ -f "${STEAMLING_REPO_PUBKEY}" ] || die "STEAMLING_REPO_PUBKEY not found: ${STEAMLING_REPO_PUBKEY}"
      install -Dm644 "${STEAMLING_REPO_PUBKEY}" "${root}/usr/share/steamling/steamling-repo.gpg"
      chroot "${root}" pacman-key --add /usr/share/steamling/steamling-repo.gpg
      local fpr
      fpr="$(gpg --show-keys --with-colons "${STEAMLING_REPO_PUBKEY}" 2>/dev/null | awk -F: '/^fpr/{print $10; exit}')"
      [ -n "${fpr}" ] || die "could not read the key fingerprint from ${STEAMLING_REPO_PUBKEY} (host gpg missing?)"
      chroot "${root}" pacman-key --lsign-key "${fpr}"
      log "repo key trusted: ${fpr}"
    fi
  fi
}

configure_keyring() {
  local root="$1"
  log "initialising pacman keyring (archlinuxarm)"
  chroot "${root}" pacman-key --init
  chroot "${root}" pacman-key --populate archlinuxarm
  # The rolling ALARM tarball can carry an older keyring than the base's packages were
  # signed with: take the base's keyring first, so the big install below verifies.
  chroot "${root}" pacman -Sy --noconfirm --needed archlinuxarm-keyring
  chroot "${root}" pacman-key --populate archlinuxarm
}

# Generate a UTF-8 locale (ALARM base is "C" only). Qt/Plasma warn + fall back to C.UTF-8 otherwise.
configure_locale() {
  local root="$1"
  log "generating en_US.UTF-8 locale"
  sed -i 's/^#\(en_US.UTF-8 UTF-8\)/\1/' "${root}/etc/locale.gen"
  chroot "${root}" locale-gen
  echo 'LANG=en_US.UTF-8' > "${root}/etc/locale.conf"
}

install_packages() {
  local root="$1"; shift
  local lists=("$@")
  local pkgs=()
  for l in "${lists[@]}"; do
    mapfile -t -O "${#pkgs[@]}" pkgs < <(read_pkglist "${l}")
  done
  log "installing ${#pkgs[@]} packages from: ${lists[*]##*/}"
  progress_detail "installing ${#pkgs[@]} base packages"
  # -Syy (force DB refresh): a reused rootfs keeps a stale sync DB, and plain -Sy won't
  # re-download a DB pacman thinks is current -> valid extra pkgs (vulkan-tools, alsa-utils,
  # alsa-ucm-conf) show up as "target not found". Safe here: this is a fresh-image -Su anyway.
  chroot "${root}" pacman "$(base_sync_flags)y" --noconfirm --needed "${pkgs[@]}"
}

# Bake the native ARM Steam client at BUILD time so first boot needs no network: the on-device
# launcher has no network-installer fallback, so an image with no seed ships a Steam session that
# hard-fails. Runs the on-device installer in the rootfs chroot under a STAGING HOME, verifies the
# tree is complete (steamui.so + the channel .installed manifest, else the seed would re-install
# online), strips per-session cruft and tars the HOME-agnostic tree (relative .steam symlinks) into
# ${CACHE_DIR}/steam-seed-<channel>.tar.zst. The tar is a BUILD-TIME INTERMEDIATE, unpacked into the rootfs
# at the end of this function and never shipped. The cache makes repeat builds offline;
# STEAMLING_REBOOTSTRAP_STEAM=1 forces a rebake.
bootstrap_steam_seed() {
  local root="$1"
  # The channel comes from the installer, and names the seed, so moving channels rebakes it.
  local channel
  channel="$(sed -n 's/^STEAM_ARM_CHANNEL="\(.*\)"$/\1/p' \
    "${STEAMLING_ROOT}/packages/shared/steamling-steam/steamling-steam-install")"
  [ -n "${channel}" ] || die "no STEAM_ARM_CHANNEL in steamling-steam-install"
  local seed="${CACHE_DIR}/steam-seed-${channel}.tar.zst"
  local home="/var/lib/steamling/steam-seed-home"
  local steam="${home}/.local/share/Steam"

  if [ ! -f "${seed}" ] || [ -n "${STEAMLING_REBOOTSTRAP_STEAM:-}" ]; then
    log "baking native ARM Steam client (downloads + Xvfb self-update; can take several minutes)..."
    progress_detail "baking the Steam client (first build only)"
    # steam/bwrap need a real writable /dev/shm. chroot_mount binds host /dev (non-recursive), so the
    # chroot has none. Make the chroot's /dev private FIRST so this tmpfs can't propagate up and
    # shadow the HOST's /dev/shm (the bind aliases the same path), then mount a private tmpfs.
    mount --make-rprivate "${root}/dev" 2>/dev/null || true
    mount -t tmpfs tmpfs "${root}/dev/shm"
    chroot "${root}" rm -rf "${home}"; chroot "${root}" mkdir -p "${home}"
    if ! chroot "${root}" env HOME="${home}" /usr/bin/steamling-steam-install; then
      umount "${root}/dev/shm" 2>/dev/null || true
      die "steam bake failed (steamling-steam-install in chroot). Check network + retry (the bake is cached, so a retry resumes)."
    fi
    if ! chroot "${root}" test -f "${steam}/steamrtarm64/steamui.so" \
       || ! chroot "${root}" test -f "${steam}/package/steam_client_${channel}_linuxarm64.installed"; then
      umount "${root}/dev/shm" 2>/dev/null || true
      die "steam bake incomplete (no steamui.so / .installed) — the seed is broken. Re-run (STEAMLING_REBOOTSTRAP_STEAM=1 forces a clean rebake)."
    fi
    # strip per-session cruft AND registry.vdf (where Steam records setup as done) so the first
    # boot gets Steam's first-run setup, which build-sd-image.sh's /etc/steamos-oobe-image turns on;
    # steamling-steamos-shim's steamos-update keeps its required-update step from dead-ending.
    # Then tar the HOME-agnostic tree.
    chroot "${root}" bash -c "set -e; cd '${home}'
      rm -rf .local/share/Steam/logs .local/share/Steam/appcache/httpcache \
             .local/share/Steam/appcache/cefdata .local/share/Steam/config/htmlcache
      find . \( -name '*.log' -o -name '*.pid' -o -name '*.token' -o -name '*.crash' \) -delete
      find . \( -type s -o -type p \) -delete
      rm -f .local/share/Steam/ssfn* .local/share/Steam/registry.vdf \
            .steam/registry.vdf .steam/steam.pid .steam/steam.token
      tar -caf /steam-seed.tar.zst .local .steam"
    mkdir -p "${CACHE_DIR}"; cp "${root}/steam-seed.tar.zst" "${seed}"
    chroot "${root}" rm -f /steam-seed.tar.zst; chroot "${root}" rm -rf "${home}"
    umount "${root}/dev/shm" 2>/dev/null || true
    ok "steam seed baked: ${seed} ($(du -h "${seed}" | cut -f1))"
  else
    log "using cached steam seed: ${seed} ($(du -h "${seed}" | cut -f1))"
  fi
  # Pre-extract the baked client into the rootfs's /home/deck HERE — while it's still part of
  # ROOTFS_DIR, so build-sd-image.sh's `du -sm ROOTFS_DIR` sizes the image partition to INCLUDE the
  # ~1.3 GB tree. (Extracting later, during image assembly into the already-sized partition, blew
  # past its size -> "No space left on device".) The tar is NOT shipped in the rootfs: we unpack the
  # cached seed straight in and drop it, so the image carries only the extracted tree. Files land
  # root-owned (bake ran as root); build-sd-image.sh creates the deck user (uid 1001) and its
  # `chown -R deck:deck /home/deck` fixes ownership. The relative .steam symlinks are HOME-agnostic
  # so they resolve correctly once this tree is deck's HOME.
  log "pre-extracting Steam client into rootfs /home/deck (sized into the partition; no tar shipped)"
  progress_detail "unpacking the Steam client"
  install -d "${root}/home/deck"
  cp "${seed}" "${root}/steam-seed.tar.zst"
  chroot "${root}" bash -c "set -e; tar -C /home/deck -xf /steam-seed.tar.zst; rm -f /steam-seed.tar.zst"
}

main() {
  # 1. base rootfs
  progress_detail "unpacking the Arch Linux ARM base"
  "${STEAMLING_ROOT}/scripts/bootstrap.sh"

  # 1b. build the local steamling-* packages (own build chroot) -> build/localrepo. make image runs
  #     this as a step of its own just before (STEAMLING_PACKAGES_DONE=1), to time it separately.
  if [ "${STEAMLING_PACKAGES_DONE:-0}" = 1 ]; then
    log "packages: built by the step before (STEAMLING_PACKAGES_DONE=1)"
  else
    "${STEAMLING_ROOT}/scripts/build-packages.sh"
  fi

  # 2. pacman config + repos inside the rootfs
  mkdir -p "${LOCAL_REPO_DIR}"
  render_pacman_conf "${ROOTFS_DIR}/etc/pacman.conf"

  trap 'umount "${ROOTFS_DIR}/localrepo" 2>/dev/null || true; chroot_umount "${ROOTFS_DIR}"' EXIT
  chroot_mount "${ROOTFS_DIR}"
  configure_keyring "${ROOTFS_DIR}"

  # 3. packages: the ALARM base only (config/packages/base.list). The session
  #    stacks (Steam/gamescope, Plasma Mobile, emulation) install later in
  #    install_local_packages as depends of the layer metapackages — the metas'
  #    depends= are the single manifest for image AND fleet.
  install_packages "${ROOTFS_DIR}" \
        "${CONFIG_DIR}/packages/base.list"

  # Generate a UTF-8 locale. The ALARM base ships only "C"; Qt apps (all of Plasma) warn and fall
  # back to C.UTF-8 on every launch, and the C path is slower. Set en_US.UTF-8 system-wide.
  configure_locale "${ROOTFS_DIR}"

  # 4. device support: the local packages (layer metas, the SoC kernel from
  #    ${KERNEL_BUILD_DIR}/out, the device set). Run `make kernel` first.
  install_local_packages "${ROOTFS_DIR}"
  prune_fontconfig_compat_links "${ROOTFS_DIR}"
  # A repo that bumped a library's soname without rebuilding everything linked to it ships
  # packages that install fine and crash on load (Plasma Mobile on libPlasma.so.7 vs .so.8: a
  # black desktop). Fail here instead of on the device.
  progress_detail "checking every program finds its libraries"
  # Package names from file names: <name>-<pkgver>-<pkgrel>-<arch>.pkg.tar.*
  local f b ours=""
  for f in "${LOCAL_REPO_DIR}"/*.pkg.tar.* "${LOCAL_REPO_SHARED_DIR}"/*.pkg.tar.*; do
    b="${f##*/}"; case "${b}" in *.sig|'*.pkg.tar.*') continue ;; esac
    b="${b%%.pkg.tar.*}"; b="${b%-*}"; b="${b%-*}"; ours+="${b%-*}"$'\n'
  done
  STEAMLING_OUR_PACKAGES="${ours}" "${STEAMLING_ROOT}/scripts/check-sonames.sh" "${ROOTFS_DIR}" \
    || die "a package in the image needs a library version the image doesn't have (listed above)"
  strip_docs "${ROOTFS_DIR}"

  # A live build has no frozen base to lock to, so mark it rolling (the flag `steamling-base
  # rolling` sets). Without it steamling-lock-migrate moves the device onto the pinned base at its
  # first update.
  if [ -z "${STEAMLING_BASE_SNAPSHOT}" ]; then
    install -d "${ROOTFS_DIR}/etc/steamling"
    echo "rolling: built from live Arch Linux ARM on $(date -u +%F). 'steamling-base locked' locks it." \
      > "${ROOTFS_DIR}/etc/steamling/rolling-mode"
  fi

  # Build stamp for support: which base snapshot this image shipped with, and
  # when. Separate file: /etc/os-release is owned by the filesystem package.
  # (A running device's CURRENT base is steamling-base-lock's version, which
  # tracks updates; this records where the image started.)
  printf 'STEAMLING_BASE_SNAPSHOT=%s\nSTEAMLING_IMAGE_BUILD=%s\n' \
    "${STEAMLING_BASE_SNAPSHOT:-live}" "$(date -u +%Y-%m-%d)" > "${ROOTFS_DIR}/etc/steamling-release"

  # 5. bake the native ARM Steam client into a re-seedable seed (offline first boot)
  bootstrap_steam_seed "${ROOTFS_DIR}"

  chroot_umount "${ROOTFS_DIR}"; trap - EXIT
  if [ "${STEAMLING_IMAGE_PKG_CACHE}" = 1 ]; then
    progress_detail "linking the package cache"
    link_installed_into_cache "${ROOTFS_DIR}"
  fi

  # The rootfs is complete. Assembling it into a flashable image (partitions, boot KERNEL,
  # first-boot config) is a separate step: scripts/build-sd-image.sh (make sd-image).
  ok "build-image: rootfs ready at ${ROOTFS_DIR} — run 'make sd-image' to assemble a flashable image"
}

main "$@"
