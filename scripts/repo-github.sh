#!/usr/bin/env bash
# repo-github.sh — host Steamling's own package repos on GitHub releases. Sourced by
# stage-repo.sh, stage-check.sh and publish-repo.sh when STEAMLING_REPO_GITHUB names a repo
# (owner/name); needs gh, logged in with write access, and a repo with at least one commit.
#
# Each tree is one release whose tag is the tree's folder name: the per-SoC [steamling] trees
# are tagged after their SoC and [steamling-shared] is tagged "shared". So with
# STEAMLING_REPO_URL at https://github.com/<owner/name>/releases/download, a device's
# <url>/<soc> and <url>/shared stanzas reach the right release with nothing GitHub-specific in
# them. A tree is a few dozen packages, far under GitHub's 1000 files a release.
#
# File names keep to letters, digits, '.', '_' and '-' (base_file_name in lib.sh): GitHub
# renames anything else, and our epoch'd packages (mesa, gamescope) have a ':' in theirs.

GHR_FILE_LIMIT=$(( 2 * 1024 * 1024 * 1024 - 1 ))

ghr_init() {
  need_tool gh
  GHR_REPO="${STEAMLING_REPO_GITHUB}"
  gh auth status >/dev/null 2>&1 || die "gh isn't logged in: run 'gh auth login' (it needs write access to ${GHR_REPO})"
  gh repo view "${GHR_REPO}" >/dev/null 2>&1 \
    || die "gh can't see ${GHR_REPO}: create it on GitHub (with a README, so it has a commit) or fix STEAMLING_REPO_GITHUB"
}

ghr_exists() { gh release view "$1" --repo "${GHR_REPO}" >/dev/null 2>&1; }

# "name size" for every file a release holds
ghr_assets() { gh release view "$1" --repo "${GHR_REPO}" --json assets --jq '.assets[] | "\(.name) \(.size)"'; }

# Make $2 an exact copy of release $1's packages and signatures: download what's missing or a
# different size, delete local package files the release doesn't have. Returns 1 when the
# release doesn't exist yet (the tree's first publish).
# "Live" is what the release's database lists, since that is all a device ever installs. An upload
# that died partway leaves new package files on the release that the database never got to name;
# taking those as live made the retry refuse them as already published.
ghr_mirror() {
  local tag="$1" dir="$2" n s f db tmp
  ghr_exists "${tag}" || return 1
  mkdir -p "${dir}"
  declare -A live=() listed=()
  tmp="$(mktemp -d)"
  db="$(ghr_assets "${tag}" | awk '$1 ~ /\.db$/ {print $1; exit}')"
  if [ -n "${db}" ] && gh release download "${tag}" --repo "${GHR_REPO}" --pattern "${db}" --dir "${tmp}" --clobber 2>/dev/null; then
    while IFS= read -r n; do listed["${n}"]=1; listed["${n}.sig"]=1
    done < <(tar -xOzf "${tmp}/${db}" --wildcards '*/desc' 2>/dev/null | awk 'f {print; f=0} /^%FILENAME%$/ {f=1}')
  fi
  rm -rf "${tmp}"
  while read -r n s; do
    [ -n "${n}" ] || continue
    case "${n}" in *.pkg.tar.*) [ "${#listed[@]}" -eq 0 ] || [ -n "${listed[${n}]:-}" ] || continue ;; esac
    live["${n}"]=1
    case "${n}" in *.pkg.tar.*) ;; *) continue ;; esac
    [ -f "${dir}/${n}" ] && [ "$(stat -c %s "${dir}/${n}")" = "${s}" ] && continue
    gh release download "${tag}" --repo "${GHR_REPO}" --pattern "${n}" --dir "${dir}" --clobber \
      || die "couldn't download ${n} from ${GHR_REPO} release ${tag}"
  done < <(ghr_assets "${tag}")
  for f in "${dir}"/*.pkg.tar.*; do
    [ -e "${f}" ] || continue
    [ -n "${live[$(basename "${f}")]:-}" ] || rm -f "${f}"
  done
}

# Publish directory $2 as release $1: packages and signatures first (only what's new), then the
# db, files and key every time (their names never change), then remove whatever the release
# holds that the directory doesn't, so old versions don't pile up.
ghr_publish() {
  local tag="$1" dir="$2" title="$3" n s f
  if ! ghr_exists "${tag}"; then
    gh release create "${tag}" --repo "${GHR_REPO}" --title "${title}" --latest=false \
      --notes "Steamling's ${tag} package repo. pacman reads these files; there is nothing to download by hand." \
      >/dev/null || die "couldn't create release ${tag} on ${GHR_REPO}"
  fi
  declare -A have=() keep=()
  while read -r n s; do [ -n "${n}" ] && have["${n}"]="${s}"; done < <(ghr_assets "${tag}")
  local todo=() meta=()
  for f in "${dir}"/*; do
    [ -f "${f}" ] || continue
    n="$(basename "${f}")"
    case "${n}" in
      *.old|*.old.*|.*) continue ;;
      *.pkg.tar.*)
        [ "$(stat -Lc %s "${f}")" -le "${GHR_FILE_LIMIT}" ] || die "${n} is over GitHub's 2 GiB a file"
        keep["${n}"]=1
        [ "${have[${n}]:-}" = "$(stat -Lc %s "${f}")" ] || todo+=("${f}") ;;
      *) keep["${n}"]=1; meta+=("${f}") ;;
    esac
  done
  local i
  if [ "${#todo[@]}" -gt 0 ]; then
    log "uploading ${#todo[@]} file(s) to ${GHR_REPO} release ${tag}"
    for ((i = 0; i < ${#todo[@]}; i += 50)); do
      gh release upload "${tag}" --repo "${GHR_REPO}" --clobber "${todo[@]:i:50}" >/dev/null \
        || die "upload to ${tag} failed; run the same command again to carry on"
    done
  fi
  [ "${#meta[@]}" -eq 0 ] || gh release upload "${tag}" --repo "${GHR_REPO}" --clobber "${meta[@]}" >/dev/null \
    || die "upload to ${tag} failed; run the same command again to carry on"
  for n in "${!have[@]}"; do
    [ -n "${keep[${n}]:-}" ] && continue
    log "removing ${n} from ${tag} (no longer published)"
    gh release delete-asset "${tag}" "${n}" --repo "${GHR_REPO}" --yes >/dev/null || die "couldn't remove ${n} from ${tag}"
  done
}
