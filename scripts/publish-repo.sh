#!/usr/bin/env bash
# publish-repo.sh — sign a repo tree and publish it as a public repo: the per-SoC
# [steamling] or the SoC-neutral [steamling-shared] (STEAMLING_REPO_SCOPE, lib.sh).
#
# The publish SOURCE is ${REPO_STAGE_DIR} (`make stage`): a mirror of the live repo with
# only the intended packages swapped in. The raw localrepo is shared mutable build output
# and is not publishable by default (why: see scripts/stage-repo.sh). `make stage` first.
#
# Publishing is: detach-sign every package, re-add them to a signed database,
# export the public key alongside, and sync the directory to the host (rclone
# remote, e.g. Cloudflare R2). Devices with the [steamling] stanza + the lsigned
# key then update with plain `pacman -Syu`. Sigs of unchanged packages came down
# with the staging mirror and are reused; only new files get signed.
#
# Config (config/steamling.conf or env):
#   STEAMLING_REPO_GPG_KEY        signing key id/email (required unless --unsigned)
#   STEAMLING_REPO_GITHUB         publish to this repo's GitHub releases instead (repo-github.sh)
#   STEAMLING_REPO_RCLONE_REMOTE  rclone destination (optional: skip upload if empty)
#
# Modes:
#   (default)    publish ${REPO_STAGE_DIR}: sign + repo-add --sign + upload.
#                Requires the .staged-ok marker from `make stage`; the marker is
#                consumed on success, so the next publish needs a fresh staging.
#   --serve      LAN testing: prepare build/localrepo/<soc> and serve it over
#                http :8000 (foreground). NEVER uploads — point the device at
#                http://<this-host>:8000/<soc>.
#   --unsigned   skip signing; only valid with --serve (pair with SigLevel
#                Optional TrustAll on the device).
#
# Escape hatch: STEAMLING_PUBLISH_FROM=localrepo publishes the raw localrepo (first-ever
# publish of a new SoC, disaster recovery). It signs + syncs + PRUNES the bucket with
# whatever the dir holds; diff against the live db before using it.
#
# Run as the user who owns the GPG key + rclone remote — NO sudo.
# Never republish the same package filename with different bytes — bump pkgrel
# instead (client caches + signatures break otherwise).

source "$(dirname "$0")/lib.sh"

REPO_DB="${REPO_NAME}.db.tar.gz"
# Scope (lib.sh): each SoC's [steamling] repo is a self-contained tree published
# under <remote>/<soc> (tuned packages share pkgnames across SoCs with
# different binaries) — run once per SoC: `make stage` + `make publish
# DEVICE=<target of that soc>`. The SoC-neutral [steamling-shared] tree lives
# under <remote>/shared — run ONCE: `make stage-shared` + `make publish-shared`.
RCLONE_DEST="${STEAMLING_REPO_RCLONE_REMOTE:+${STEAMLING_REPO_RCLONE_REMOTE}/${REPO_SEG}}"
unsigned=0 serve=0
for a in "$@"; do
  case "$a" in
    --unsigned) unsigned=1 ;;
    --serve)    serve=1 ;;
    *) die "unknown arg: $a (known: --unsigned --serve)" ;;
  esac
done
[ "${unsigned}" -eq 0 ] || [ "${serve}" -eq 1 ] \
  || die "--unsigned is LAN-testing only — pair it with --serve (an unsigned upload would break every device)"

# --- publish source selection (the heart of the staging workflow) ------------
MARKER=""
if [ "${serve}" -eq 1 ]; then
  # LAN testing serves the raw build output (test packages are the point) and
  # never uploads, so nothing can leak to the live repo.
  SRC="${REPO_LOCALREPO_DIR}"
  RCLONE_DEST=""
  [ -d "${SRC}" ] || die "no ${SRC} — run 'make packages' first"
elif [ "${STEAMLING_PUBLISH_FROM:-stage}" = "localrepo" ]; then
  SRC="${REPO_LOCALREPO_DIR}"
  [ -d "${SRC}" ] || die "no ${SRC} — run 'make packages' first"
  warn "publishing the RAW localrepo (shared build output, bucket will be pruned to match it)"
  warn "diff it against the live db first if you have not already"
elif [ "${STEAMLING_PUBLISH_FROM:-stage}" = "stage" ]; then
  SRC="${REPO_STAGE_DIR}"
  MARKER="${REPO_STAGE_DIR}/.staged-ok"
  [ -f "${MARKER}" ] || die "no staged release — run 'make stage PKG=\"...\"' first
(publish sources ${REPO_STAGE_DIR}, never the raw localrepo; see scripts/stage-repo.sh)"
  stale="$(find "${SRC}" -name '*.pkg.tar.*' -newer "${MARKER}" -print -quit)"
  [ -z "${stale}" ] || die "stage dir changed after staging ($(basename "${stale}")) — re-run make stage"
else
  die "STEAMLING_PUBLISH_FROM=${STEAMLING_PUBLISH_FROM} (known: stage, localrepo)"
fi

shopt -s nullglob
# package files, excluding detached signatures (which match the same glob)
pkgs=()
for p in "${SRC}"/*.pkg.tar.*; do [[ "$p" == *.sig ]] || pkgs+=("$p"); done
[ "${#pkgs[@]}" -gt 0 ] || die "no packages in ${SRC}"

# --- GitHub releases (STEAMLING_REPO_GITHUB): scripts/repo-github.sh -------------------------
# Signed and indexed in a copy under build/publish/repo/<tree>, under GitHub-safe names, so the
# source dir (the stage, or the build's own localrepo on a first publish) is never touched.
if [ -n "${STEAMLING_REPO_GITHUB}" ] && [ "${serve}" -eq 0 ]; then
  source "$(dirname "$0")/repo-github.sh"
  ghr_init
  [ -n "${STEAMLING_REPO_GPG_KEY}" ] || die "STEAMLING_REPO_GPG_KEY unset: devices only take signed packages
  one-time key setup: gpg --quick-gen-key 'Steamling Packaging <you@example.com>' ed25519 sign 2y"
  need_tool gpg
  need_tool cmp
  PUB="${BUILD_DIR}/publish/repo/${REPO_SEG}"
  mkdir -p "${PUB}" 2>/dev/null && [ -w "${PUB}" ] || die "${PUB} isn't writable: sudo install -d -o $(id -un) ${PUB}"
  declare -A want=()
  for p in "${pkgs[@]}"; do
    n="$(base_file_name "$(basename "${p}")")"; want["${n}"]=1
    if [ ! -f "${PUB}/${n}" ] || ! cmp -s "${p}" "${PUB}/${n}"; then
      cp -f "${p}" "${PUB}/${n}"; rm -f "${PUB}/${n}.sig"
    fi
    # a signature that came down with the live files is reused
    [ -f "${PUB}/${n}.sig" ] || { [ -f "${p}.sig" ] && [ ! "${p}" -nt "${p}.sig" ] && cp -f "${p}.sig" "${PUB}/${n}.sig"; } || true
  done
  for f in "${PUB}"/*; do
    n="$(basename "${f}")"; n="${n%.sig}"
    case "${n}" in *.pkg.tar.*) [ -n "${want[${n}]:-}" ] || rm -f "${f}" ;; *) rm -f "${f}" ;; esac
  done
  log "signing ${#pkgs[@]} packages with ${STEAMLING_REPO_GPG_KEY}"
  for f in "${PUB}"/*.pkg.tar.*; do
    case "${f}" in *.sig) continue ;; esac
    [ -f "${f}.sig" ] || gpg --detach-sign --no-armor --yes -u "${STEAMLING_REPO_GPG_KEY}" "${f}" \
      || die "gpg sign failed for ${f}"
  done
  log "building the signed ${REPO_NAME} database"
  ( cd "${PUB}" && ls *.pkg.tar.* | grep -v '\.sig$' | LC_ALL=C xargs repo-add --sign --key "${STEAMLING_REPO_GPG_KEY}" -q "${REPO_DB}" ) \
    || die "repo-add --sign failed"
  rm -f "${PUB}"/*.old "${PUB}"/*.old.sig
  gpg --export --armor "${STEAMLING_REPO_GPG_KEY}" > "${PUB}/steamling-repo.gpg"
  ghr_publish "${REPO_SEG}" "${PUB}" "Steamling packages: ${REPO_SEG}"
  [ -n "${MARKER}" ] && rm -f "${MARKER}"
  ok "published ${REPO_SEG} to ${STEAMLING_REPO_GITHUB} (${STEAMLING_REPO_PUBLIC}/${REPO_SEG})"
  exit 0
fi

if [ "${unsigned}" -eq 0 ]; then
  [ -n "${STEAMLING_REPO_GPG_KEY}" ] || die "STEAMLING_REPO_GPG_KEY unset (or pass --unsigned for LAN testing)
  one-time key setup: gpg --quick-gen-key 'Steamling Packaging <you@example.com>' ed25519 sign 2y"
  need_tool gpg
  log "signing ${#pkgs[@]} packages with ${STEAMLING_REPO_GPG_KEY}"
  for p in "${pkgs[@]}"; do
    # re-sign only when missing or older than the package (idempotent republish)
    if [ ! -f "${p}.sig" ] || [ "${p}" -nt "${p}.sig" ]; then
      gpg --detach-sign --no-armor --yes -u "${STEAMLING_REPO_GPG_KEY}" "${p}" \
        || die "gpg sign failed for ${p} (root-owned file? chown or sudo -E)"
    fi
  done
  log "rebuilding signed repo database"
  ( cd "${SRC}" && repo-add --sign --key "${STEAMLING_REPO_GPG_KEY}" -q "${REPO_DB}" "${pkgs[@]}" ) \
    || die "repo-add --sign failed (is repo-add installed? 'pacman' package on the VM)"
  # export the public key next to the repo so devices can fetch + lsign it
  gpg --export --armor "${STEAMLING_REPO_GPG_KEY}" > "${SRC}/steamling-repo.gpg"
  ok "signed: packages + ${REPO_DB} + steamling-repo.gpg"
else
  # no repo-add here: the localrepo db is already maintained by build-packages.sh
  warn "preparing UNSIGNED (LAN testing only — device stanza needs SigLevel = Optional TrustAll)"
fi

if [ -n "${RCLONE_DEST}" ]; then
  need_tool rclone
  log "syncing -> ${RCLONE_DEST}"
  # order matters for a window-free publish: packages+sigs first, database last, so a
  # client never sees a db entry whose package isn't uploaded yet.
  # -L/--copy-links: repo-add makes steamling.db / steamling.files (the exact names pacman
  # fetches) SYMLINKS to the .tar.gz; without -L rclone skips them and the device 404s
  # on the db. --exclude '*.old*': repo-add's local backups are not for publishing.
  rclone copy --include '*.pkg.tar.*' --exclude '*.old*' "${SRC}" "${RCLONE_DEST}"
  rclone copy -L --include "${REPO_NAME}.db*" --include "${REPO_NAME}.files*" --include 'steamling-repo.gpg' \
    --exclude '*.old*' "${SRC}" "${RCLONE_DEST}"
  # prune package versions that no longer exist locally (keeps the bucket bounded)
  rclone sync -L --exclude '*.old*' --exclude '.staged-ok' "${SRC}" "${RCLONE_DEST}"
  # remove any *.old* already in the bucket (idempotent; harmless if none)
  rclone delete --include '*.old*' "${RCLONE_DEST}" 2>/dev/null || true
  # consume the staging marker: the next publish must go through a fresh
  # `make stage` (which re-mirrors live), so stale stagings cannot be re-shipped
  [ -n "${MARKER}" ] && rm -f "${MARKER}"
  ok "published to ${RCLONE_DEST}"
elif [ "${serve}" -eq 0 ]; then
  warn "STEAMLING_REPO_RCLONE_REMOTE unset — nothing uploaded (repo prepared in ${SRC})"
fi

if [ "${serve}" -eq 1 ]; then
  need_tool python3
  ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  # serve the PARENT dir: shipped stanzas point at <base>/<soc>, so the URL path
  # must include the SoC segment (matches images built with STEAMLING_REPO_URL=http://<vm-ip>:8000)
  log "serving ${BUILD_DIR}/localrepo on http://${ip:-<this-host>}:8000 (Ctrl-C to stop; nothing was uploaded)"
  log "device stanza:  [${REPO_NAME}]  SigLevel = Optional TrustAll  Server = http://${ip:-<vm-ip>}:8000/${REPO_SEG}"
  python3 -m http.server 8000 -d "${BUILD_DIR}/localrepo"
fi
