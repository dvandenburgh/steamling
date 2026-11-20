#!/usr/bin/env bash
# seed-localrepo.sh — download into build/localrepo every PUBLISHED [steamling] / [steamling-shared]
# package that is exactly the version this checkout builds, so `make build` compiles only what
# differs. The image build installs solely from build/localrepo, so without this an x86 host
# under qemu compiles every package (mesa, gamescope, FEX, the emulators) before the first image.
# Root, like the other build steps.

source "$(dirname "$0")/lib.sh"
need_root seed
for t in curl bsdtar awk; do need_tool "$t"; done
[ -n "${STEAMLING_REPO_URL}" ] || die "STEAMLING_REPO_URL is empty: no published repo to seed from"

published() {  # <tree> <db name> -> "name filename" per package
  curl -fsSL --retry 3 "${STEAMLING_REPO_URL}/$1/$2.db" | bsdtar -xOf - \
    | awk '/^%FILENAME%$/{getline f} /^%NAME%$/{getline n; print n, f}'
}
# A tree that isn't published yet (a new family, or before the first publish) just means its
# packages compile, so it warns instead of stopping the build.
soc_list="$(published "${SOC}" steamling)" || { warn "nothing published at ${STEAMLING_REPO_URL}/${SOC} yet"; soc_list=""; }
shared_list="$(published shared steamling-shared)" || { warn "nothing published at ${STEAMLING_REPO_URL}/shared yet"; shared_list=""; }
# Keyed by the local repo a package builds into, so a copy published in the other tree (the
# per-SoC repo's steamling-base bridge) is never taken for a shared package.
declare -A pub=()
while read -r name file; do [ -n "${name}" ] && pub["${LOCALREPO_DIR}|${name}"]="${SOC}/${file}"; done <<< "${soc_list}"
while read -r name file; do [ -n "${name}" ] && pub["${LOCALREPO_SHARED_DIR}|${name}"]="shared/${file}"; done <<< "${shared_list}"

# An interrupted download must not be left where a package would be looked for.
part=""
trap '[ -z "${part}" ] || rm -f "${part}"' EXIT

got=0 have=0 differ=0
log "seeding build/localrepo from ${STEAMLING_REPO_URL}"
while IFS='|' read -r repo d p v a; do
  # sd-image boots this host's `make kernel` and syncs its modules: never a published kernel.
  [ "${p}" = "${KERNEL_PKG}" ] && continue
  # A local copy at this version counts only while build-packages.sh would skip it. A pull
  # rewrites files (and their mtimes) without a pkgrel bump, so an older copy would be compiled
  # again although the published one is this version.
  if f="$(artifact_file "${repo}" "${p}-${v}-${a}")" && artifact_current "${f}" "${d}" "${p}"; then
    have=$((have + 1)); continue
  fi
  src="${pub["${repo}|${p}"]:-}"
  # Published under its GitHub-safe name (an epoch's ':' becomes '_'), kept here under the real
  # one, which is what build-packages.sh looks for.
  case "${src##*/}" in
    "${p}-${v}-${a}.pkg.tar."*|"$(base_file_name "${p}-${v}-${a}").pkg.tar."*) ;;
    *) differ=$((differ + 1)); continue ;;
  esac
  dest="${p}-${v}-${a}.pkg.tar.${src##*.pkg.tar.}"
  # A fresh download is newer than every file in the package dir, so build-packages.sh would
  # skip uncommitted edits there. Run as root on the user's checkout, hence safe.directory.
  if [ -n "$(git -c safe.directory='*' -C "${d}" status --porcelain -- . 2>/dev/null)" ]; then
    warn "  ${p}: ${d#"${STEAMLING_ROOT}"/} has uncommitted changes, so 'make build' compiles it"
    differ=$((differ + 1)); continue
  fi
  mkdir -p "${repo}"
  log "  ${src}"
  progress_detail "downloading ${src##*/}"
  # Dot-named so neither the clean-up below nor build-packages.sh's `ls *.pkg.tar.*` sees it.
  part="${repo}/.${src##*/}.part"
  curl -fsSL --retry 3 -o "${part}" "${STEAMLING_REPO_URL}/${src}" || die "download failed: ${STEAMLING_REPO_URL}/${src}"
  # One version per package, as build-packages.sh keeps it: a second breaks `pacman -U` and
  # leaves the repo db on whichever repo-add saw last.
  rm -f "${repo}/${p}"-[0-9]*.pkg.tar.* "${repo}/${p}"-*:*.pkg.tar.*
  mv "${part}" "${repo}/${dest}"; part=""
  got=$((got + 1))
done < <(local_artifacts)

ok "${got} downloaded, ${have} already in build/localrepo, ${differ} to compile (not published at this checkout's version)"
log "'make pending' lists what 'make build' will compile"
