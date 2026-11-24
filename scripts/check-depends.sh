#!/usr/bin/env bash
# check-depends.sh - check-depends.py over everything in the local repos, against the live base
# (make check-depends; it also runs after every package build, so a gap stops ./build.sh before
# the rootfs). A package that needs something it doesn't declare works until whatever brought that
# in goes away. The details are in scripts/check-depends.py.
source "$(dirname "$0")/lib.sh"
for t in python3 zstd curl; do need_tool "$t"; done
shopt -s nullglob

cache="${BUILD_DIR}/.depends-cache"
mkdir -p "${cache}"
# The base's package list and file list, as devices see them. Offline is no reason to fail a
# build: skip with a warning and let make stage catch it.
for k in db files; do
  if ! curl -fsSL --retry 2 --connect-timeout 15 -o "${cache}/base.${k}.part" \
       "${STEAMLING_BASE_URL}/${STEAMLING_BASE_REPO}.${k}.tar.gz"; then
    rm -f "${cache}/base.${k}.part"
    warn "check-depends: cannot fetch the base's ${k} list from ${STEAMLING_BASE_URL}; skipped (make stage checks again)"
    exit 0
  fi
  mv -f "${cache}/base.${k}.part" "${cache}/base.${k}.tar.gz"
done

repos=(--repo "${cache}/base.db.tar.gz:${cache}/base.files.tar.gz")
dirs=()
for db in "${BUILD_DIR}"/localrepo/*/steamling*.db.tar.gz; do
  files="${db%.db.tar.gz}.files.tar.gz"
  [ -f "${files}" ] && repos+=(--repo "${db}:${files}") || repos+=(--repo "${db}")
  dirs+=("$(dirname "${db}")")
done
[ "${#dirs[@]}" -gt 0 ] || { warn "check-depends: no local repo under ${BUILD_DIR}/localrepo yet"; exit 0; }

log "checking what our built packages need against base ${STEAMLING_BASE_SNAPSHOT:-(live)}"
if python3 "${STEAMLING_ROOT}/scripts/check-depends.py" "${repos[@]}" \
     --ok "${CONFIG_DIR}/packages/depends-ok.list" --pending "${CONFIG_DIR}/packages/depends-pending.list" \
     "${dirs[@]}" | sed 's/^/  /'; [ "${PIPESTATUS[0]}" -eq 0 ]; then
  ok "every built package declares what it needs"
else
  die "packages above need something they don't declare: add it to their depends (or, with a reason,
  to config/packages/depends-ok.list) and rebuild them"
fi
