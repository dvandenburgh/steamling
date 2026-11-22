#!/usr/bin/env bash
# publish-sources.sh — keep Steamling's own copies of the files its packages download from the
# Arch Linux Archive (make publish-sources; run as yourself, no sudo).
#
# fex-rootfs, steamling-turnip-x86 and fex-emu pin old x86_64 Arch packages, and
# archive.archlinux.org is the only place those stay. When it's down, nothing that needs them
# can build. This uploads the copies the last build left in its source cache to the "sources"
# release of STEAMLING_REPO_GITHUB, and build-packages.sh fills the cache from that release
# before makepkg goes looking. A file is only uploaded, and only taken back, when its sha256
# matches the PKGBUILD's, so the copies are byte-for-byte Arch's.
#
# Run it after a build that downloaded something new from the archive (a pin bump). Files
# already on the release are skipped; nothing is ever deleted from it.

source "$(dirname "$0")/lib.sh"
source "${STEAMLING_ROOT}/scripts/repo-github.sh"

[ -n "${STEAMLING_REPO_GITHUB}" ] || die "STEAMLING_REPO_GITHUB is empty, so there's nowhere to keep the copies"
[ "$(id -u)" -ne 0 ] || die "run this as yourself, not with sudo: gh keeps its login in your account"
ghr_init

CACHE="${BUILD_DIR}/pkgbuild-root-${SOC}/build/srccache"
TAG=sources
[ -d "${CACHE}" ] || die "no source cache at ${CACHE}: build the packages first (sudo make packages PKG=\"fex-emu fex-rootfs steamling-turnip-x86\")"

declare -A seen=()
todo=() missing=() bad=()
for d in "${PACKAGES_DIR}"/shared/*/ "${PACKAGES_DIR}"/soc/*/; do
  [ -f "${d}PKGBUILD" ] || continue
  while read -r n sum; do
    [ -n "${n}" ] && [ -z "${seen[${n}]:-}" ] || continue
    seen["${n}"]=1
    f="${CACHE}/${n}"
    if [ ! -e "${f}" ]; then
      missing+=("${n} ($(basename "${d}"))")
    elif [ ! -r "${f}" ]; then
      die "can't read ${f}: sudo chmod a+r ${CACHE}/*.pkg.tar.zst, then run this again"
    elif [ "$(sha256sum "${f}" | cut -d' ' -f1)" != "${sum}" ]; then
      bad+=("${n} ($(basename "${d}"))")
    else
      todo+=("${f}")
    fi
  done < <(archive_sources "${d}")
done

if ! ghr_exists "${TAG}"; then
  gh release create "${TAG}" --repo "${GHR_REPO}" --title "Build sources" --latest=false \
    --notes "Copies of the pinned Arch Linux packages Steamling's build downloads from archive.archlinux.org, so a build still works while the archive is down. The build reads these; there is nothing to download by hand." \
    >/dev/null || die "couldn't create release ${TAG} on ${GHR_REPO}"
fi
declare -A have=()
while read -r n s; do [ -n "${n}" ] && have["${n}"]="${s}"; done < <(ghr_assets "${TAG}")

up=()
for f in ${todo[@]+"${todo[@]}"}; do
  n="$(base_file_name "$(basename "${f}")")"
  [ "${have[${n}]:-}" = "$(stat -c %s "${f}")" ] && continue
  # upload under the name GitHub will keep (build-packages.sh asks for the same one)
  if [ "${n}" != "$(basename "${f}")" ]; then
    mkdir -p "${BUILD_DIR}/publish/sources"
    cp -f "${f}" "${BUILD_DIR}/publish/sources/${n}"
    f="${BUILD_DIR}/publish/sources/${n}"
  fi
  up+=("${f}")
done
if [ "${#up[@]}" -gt 0 ]; then
  log "uploading ${#up[@]} file(s) to ${GHR_REPO} release ${TAG}"
  for ((i = 0; i < ${#up[@]}; i += 20)); do
    gh release upload "${TAG}" --repo "${GHR_REPO}" --clobber "${up[@]:i:20}" >/dev/null \
      || die "upload to ${TAG} failed; run 'make publish-sources' again to carry on"
  done
fi
ok "${#todo[@]} file(s) kept on ${GHR_REPO} release ${TAG} (${#up[@]} new this time)"

for x in ${bad[@]+"${bad[@]}"}; do warn "doesn't match its PKGBUILD's sha256, not uploaded: ${x}"; done
if [ "${#missing[@]}" -gt 0 ]; then
  warn "not in the build's source cache, so not saved yet:"
  for x in "${missing[@]}"; do warn "  ${x}"; done
  warn "rebuild those packages while the archive is up, then run 'make publish-sources' again"
fi
