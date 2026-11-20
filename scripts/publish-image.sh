#!/usr/bin/env bash
# publish-image.sh — compress, checksum, and upload the SD image for public download
# (make publish-image).
#
# The image is for first installs, so publishing one is: xz-compress it under a version- and
# date-stamped name, write a sha256, and upload the pair. xz because balenaEtcher, Rufus and
# Raspberry Pi Imager all write a .img.xz straight to the card, no unpacking first. The name is
# date-stamped because a public file must never change bytes under the same name.
#
# Where it goes (config/steamling.conf, config/local.conf or env):
#   STEAMLING_IMAGE_GITHUB         a GitHub repo (owner/name): the image goes on a DRAFT release
#                                  for this version, v<version>, which you look over and publish
#                                  on GitHub yourself. Run again for each device family; each
#                                  family's file sits side by side on the same release.
#   STEAMLING_IMAGE_RCLONE_REMOTE  used when STEAMLING_IMAGE_GITHUB is empty: an rclone
#                                  destination, e.g. r2:steamling/images
#   STEAMLING_IMAGE_URL            public address of that destination, for the printed link
#
# Run it as yourself, not with sudo: gh and rclone keep their logins in your account. The
# compressed copy goes in build/publish.

source "$(dirname "$0")/lib.sh"

IMG="${IMAGE_DIR}/steamling-${SOC}-sd.img"
STAMP="$(date +%Y%m%d)"
# the version and codename the image itself reports (Steam's Settings > System)
OSR="${PACKAGES_DIR}/shared/steamling-base/steamling-os-release"
VERSION="$(sed -n 's/^STEAMLING_VERSION=//p' "${OSR}" | head -1)"
CODENAME="$(sed -n 's/^STEAMLING_CODENAME=//p' "${OSR}" | head -1)"
[ -n "${VERSION}" ] || die "can't read STEAMLING_VERSION from ${OSR}"
# build/publish, not next to the image: the image dir is root's after a build, and gh's login is yours
PUB_DIR="${BUILD_DIR}/publish"
OUT="${PUB_DIR}/steamling-${SOC}-${VERSION}-${STAMP}-sd.img.xz"
# GitHub refuses release files of 2 GiB or more
GH_FILE_LIMIT=$(( 2 * 1024 * 1024 * 1024 - 1 ))

[ -f "${IMG}" ] || die "no ${IMG} — run 'make sd-image' first"
need_tool xz
need_tool sha256sum
mkdir -p "${PUB_DIR}" 2>/dev/null && [ -w "${PUB_DIR}" ] || die "${PUB_DIR} isn't writable: sudo install -d -o $(id -un) ${PUB_DIR}"

if [ ! -f "${OUT}" ] || [ "${IMG}" -nt "${OUT}" ]; then
  log "compressing $(du -h "${IMG}" | cut -f1) image -> $(basename "${OUT}") (xz, all cores; a few minutes)"
  xz -T0 -6 -k -c "${IMG}" > "${OUT}.part" && mv -f "${OUT}.part" "${OUT}" \
    || { rm -f "${OUT}.part"; die "xz failed"; }
else
  log "$(basename "${OUT}") is up to date — skipping compression"
fi

log "writing sha256"
( cd "${PUB_DIR}" && sha256sum "$(basename "${OUT}")" > "${OUT}.sha256" )
ok "prepared: $(basename "${OUT}") ($(du -h "${OUT}" | cut -f1)) + .sha256"

if [ -n "${STEAMLING_IMAGE_GITHUB}" ]; then
  need_tool gh
  gh auth status >/dev/null 2>&1 || die "gh isn't logged in: run 'gh auth login' (it needs write access to ${STEAMLING_IMAGE_GITHUB})"
  size="$(stat -c %s "${OUT}")"
  [ "${size}" -le "${GH_FILE_LIMIT}" ] \
    || die "$(basename "${OUT}") is $(du -h "${OUT}" | cut -f1), and GitHub takes at most 2 GiB per file. Nothing was uploaded."
  repo="${STEAMLING_IMAGE_GITHUB}" tag="v${VERSION}"
  title="Steamling ${VERSION}${CODENAME:+ \"${CODENAME^}\"}"
  if ! gh release view "${tag}" --repo "${repo}" >/dev/null 2>&1; then
    notes="$(mktemp)"; trap 'rm -f "${notes}"' EXIT
    cat > "${notes}" <<EOF
> [!WARNING]
> Steamling is new and experimental. It can break, and installing it means replacing your
> handheld's bootloader. Go in with that in mind.

## Install

Download the \`.img.xz\` for your handheld (\`sm8550\` is the Retroid Pocket 6 and the other
Snapdragon 8 Gen 2 handhelds) and write it to a microSD card with
[balenaEtcher](https://etcher.balena.io/), Rufus or Raspberry Pi Imager. There's no need to unpack
it first. Then follow the [install guide](https://github.com/${repo}/blob/main/docs/install.md).

Each image has a \`.sha256\` next to it if you'd like to check your download:
\`sha256sum -c <file>.sha256\`.

## What's new

(fill in before publishing)
EOF
    log "creating draft release ${tag} on ${repo}"
    gh release create "${tag}" --repo "${repo}" --draft --title "${title}" --notes-file "${notes}" >/dev/null \
      || die "couldn't create release ${tag} on ${repo}"
  fi
  # An earlier image of this family on the same release (another day's build) makes way for this one.
  while read -r old; do
    case "${old}" in
      "$(basename "${OUT}")"|"$(basename "${OUT}").sha256") ;;
      "steamling-${SOC}-"*"-sd.img."*)
        log "replacing ${old}"
        gh release delete-asset "${tag}" "${old}" --repo "${repo}" --yes >/dev/null || die "couldn't remove ${old}" ;;
    esac
  done < <(gh release view "${tag}" --repo "${repo}" --json assets --jq '.assets[].name')
  # image first, checksum last: a visible .sha256 implies the image is complete
  log "uploading $(basename "${OUT}") to ${repo} release ${tag} (this takes a while)"
  gh release upload "${tag}" --repo "${repo}" --clobber "${OUT}" >/dev/null || die "upload failed; run 'make publish-image' again"
  gh release upload "${tag}" --repo "${repo}" --clobber "${OUT}.sha256" >/dev/null || die "upload failed; run 'make publish-image' again"
  ok "uploaded to release ${tag}"
  if gh release view "${tag}" --repo "${repo}" --json isDraft --jq .isDraft 2>/dev/null | grep -qx true; then
    log "it's a draft: fill in what's new and publish it at https://github.com/${repo}/releases"
  fi
elif [ -n "${STEAMLING_IMAGE_RCLONE_REMOTE}" ]; then
  need_tool rclone
  log "uploading -> ${STEAMLING_IMAGE_RCLONE_REMOTE}"
  # image first, checksum last: a visible .sha256 implies the image is complete
  rclone copy --progress "${OUT}" "${STEAMLING_IMAGE_RCLONE_REMOTE}/"
  rclone copy "${OUT}.sha256" "${STEAMLING_IMAGE_RCLONE_REMOTE}/"
  ok "uploaded"
  if [ -n "${STEAMLING_IMAGE_URL}" ]; then
    log "download link: ${STEAMLING_IMAGE_URL}/$(basename "${OUT}")"
  fi
else
  warn "STEAMLING_IMAGE_GITHUB and STEAMLING_IMAGE_RCLONE_REMOTE are both unset — nothing uploaded (artifacts left in ${PUB_DIR})"
fi
