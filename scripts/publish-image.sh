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
#   STEAMLING_IMAGE_SOURCEFORGE    a SourceForge project: the image and its .sha256 go to the
#                                  <version> folder there, over rsync and SSH as
#                                  STEAMLING_IMAGE_SOURCEFORGE_USER. Needed for any image over 2 GiB.
#   STEAMLING_IMAGE_GITHUB         a GitHub repo (owner/name): the image goes on a DRAFT release
#                                  for this version, v<version>, which you look over and publish
#                                  on GitHub yourself. Run again for each device family; each
#                                  family's file sits side by side on the same release. With
#                                  SourceForge set, the release gets the .sha256 and a link instead.
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

name="$(basename "${OUT}")"
dl=""   # where people download the image from, once it's up somewhere

# The image is far over GitHub's 2 GiB a file, so when a SourceForge project is set it goes there,
# and the GitHub release links to it.
if [ -n "${STEAMLING_IMAGE_SOURCEFORGE}" ]; then
  need_tool rsync
  need_tool ssh
  [ -n "${STEAMLING_IMAGE_SOURCEFORGE_USER}" ] \
    || die "set STEAMLING_IMAGE_SOURCEFORGE_USER to your SourceForge username in config/local.conf"
  sf="${STEAMLING_IMAGE_SOURCEFORGE_USER}@frs.sourceforge.net:/home/frs/project/${STEAMLING_IMAGE_SOURCEFORGE}/${VERSION}/"
  # image first, checksum last: a visible .sha256 implies the image is complete. --partial lets
  # an interrupted upload carry on instead of starting over.
  log "uploading ${name} to SourceForge (${STEAMLING_IMAGE_SOURCEFORGE}, folder ${VERSION}); this takes a while"
  rsync -e ssh --partial --progress --mkpath --chmod=F644 "${OUT}" "${sf}" \
    || die "upload to SourceForge failed; run 'make publish-image' again to carry on"
  rsync -e ssh --chmod=F644 "${OUT}.sha256" "${sf}" || die "upload to SourceForge failed; run 'make publish-image' again"
  dl="https://sourceforge.net/projects/${STEAMLING_IMAGE_SOURCEFORGE}/files/${VERSION}/${name}/download"
  ok "on SourceForge: ${dl}"
fi

if [ -n "${STEAMLING_IMAGE_GITHUB}" ]; then
  need_tool gh
  gh auth status >/dev/null 2>&1 || die "gh isn't logged in: run 'gh auth login' (it needs write access to ${STEAMLING_IMAGE_GITHUB})"
  repo="${STEAMLING_IMAGE_GITHUB}" tag="v${VERSION}"
  title="Steamling ${VERSION}${CODENAME:+ \"${CODENAME^}\"}"
  if [ -z "${dl}" ]; then
    [ "$(stat -c %s "${OUT}")" -le "${GH_FILE_LIMIT}" ] \
      || die "${name} is $(du -h "${OUT}" | cut -f1), and GitHub takes at most 2 GiB per file. Set STEAMLING_IMAGE_SOURCEFORGE to host it there instead. Nothing was uploaded."
  fi
  notes="$(mktemp)"; trap 'rm -f "${notes}"' EXIT
  if ! gh release view "${tag}" --repo "${repo}" >/dev/null 2>&1; then
    cat > "${notes}" <<EOF
> [!WARNING]
> Steamling is new and experimental. It can break, and installing it means replacing your
> handheld's bootloader. Go in with that in mind.

## Download

Pick the image for your handheld's chip family (the
[device list](https://github.com/${repo}/blob/main/docs/devices.md) says which one yours is):

<!-- downloads -->

## Install

Write the \`.img.xz\` to a microSD card with [balenaEtcher](https://etcher.balena.io/), Rufus or
Raspberry Pi Imager. There's no need to unpack it first. Then follow the
[install guide](https://github.com/${repo}/blob/main/docs/install.md).

The \`.sha256\` files below let you check a download: put one next to its image and run
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
      "${name}"|"${name}.sha256") ;;
      "steamling-${SOC}-"*"-sd.img."*)
        log "replacing ${old}"
        gh release delete-asset "${tag}" "${old}" --repo "${repo}" --yes >/dev/null || die "couldn't remove ${old}" ;;
    esac
  done < <(gh release view "${tag}" --repo "${repo}" --json assets --jq '.assets[].name')
  if [ -z "${dl}" ]; then
    log "uploading ${name} to ${repo} release ${tag} (this takes a while)"
    gh release upload "${tag}" --repo "${repo}" --clobber "${OUT}" >/dev/null || die "upload failed; run 'make publish-image' again"
    dl="https://github.com/${repo}/releases/download/${tag}/${name}"
  fi
  gh release upload "${tag}" --repo "${repo}" --clobber "${OUT}.sha256" >/dev/null || die "upload failed; run 'make publish-image' again"
  # This family's download line in the notes, replacing the one an earlier build wrote. Notes
  # someone rewrote without the marker get a Download section added at the end instead.
  gh release view "${tag}" --repo "${repo}" --json body --jq .body > "${notes}" \
    || die "couldn't read the notes of release ${tag}"
  line="- **${SOC}**: [${name}](${dl}) <!-- image:${SOC} -->"
  grep -q '<!-- downloads -->' "${notes}" || printf '\n## Download\n\n<!-- downloads -->\n' >> "${notes}"
  awk -v soc="<!-- image:${SOC} -->" -v line="${line}" \
    'index($0, soc) { next } { print } /<!-- downloads -->/ { print line }' "${notes}" > "${notes}.new" \
    && mv -f "${notes}.new" "${notes}"
  gh release edit "${tag}" --repo "${repo}" --notes-file "${notes}" >/dev/null || die "couldn't update the notes of release ${tag}"
  ok "release ${tag} links ${name}"
  if gh release view "${tag}" --repo "${repo}" --json isDraft --jq .isDraft 2>/dev/null | grep -qx true; then
    log "it's a draft: fill in what's new and publish it at https://github.com/${repo}/releases"
  fi
elif [ -z "${dl}" ] && [ -n "${STEAMLING_IMAGE_RCLONE_REMOTE}" ]; then
  need_tool rclone
  log "uploading -> ${STEAMLING_IMAGE_RCLONE_REMOTE}"
  # image first, checksum last: a visible .sha256 implies the image is complete
  rclone copy --progress "${OUT}" "${STEAMLING_IMAGE_RCLONE_REMOTE}/"
  rclone copy "${OUT}.sha256" "${STEAMLING_IMAGE_RCLONE_REMOTE}/"
  ok "uploaded"
  if [ -n "${STEAMLING_IMAGE_URL}" ]; then
    log "download link: ${STEAMLING_IMAGE_URL}/${name}"
  fi
elif [ -z "${dl}" ]; then
  warn "no image destination is set (STEAMLING_IMAGE_SOURCEFORGE, _GITHUB or _RCLONE_REMOTE) — nothing uploaded (artifacts left in ${PUB_DIR})"
fi
