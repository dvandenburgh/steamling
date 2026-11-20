#!/usr/bin/env bash
# base-github.sh — host the frozen base on GitHub releases. Sourced by snapshot-base.sh and
# extend-base.sh when STEAMLING_BASE_GITHUB names a repo (owner/name); needs gh, logged in
# with write access to that repo, and a repo with at least one commit (releases hang off tags).
#
# A GitHub release holds at most 1000 files and a base is over 2000 (each package plus its
# signature), so one base is spread over a few releases, its "parts". STEAMLING_BASE_URL is the
# first part's download address, .../releases/download/<tag>, and part N is <tag>-N. The first
# part carries the db, the lockfile, SNAPSHOT_ID and the dated tarball as well as packages.
# pacman's conf lists the other parts as CacheServer lines: it tries those first, takes a 404
# from one without a word, and never asks them for the db. So any package is found whichever
# part it is in, and the count is pinned as STEAMLING_BASE_PARTS.
#
# The tags never change, so devices never need repointing, the same as on R2. A new cut goes up
# under <tag>-next first and only then swaps in: the live base is renamed to <tag>-prev (what
# keeps the previous release rebuildable), and the old -prev is deleted. Renaming a release
# moves its files with it, so nothing is uploaded twice.

GH_PART_CAP=900     # files planned per part; the rest of GitHub's 1000 is room for extend-base
GH_ASSET_LIMIT=1000

gh_base_init() {
  need_tool gh
  need_tool curl
  GH_REPO="${STEAMLING_BASE_GITHUB}"
  local prefix="https://github.com/${GH_REPO}/releases/download/"
  case "${STEAMLING_BASE_URL}" in
    "${prefix}"?*) GH_TAG="${STEAMLING_BASE_URL#"${prefix}"}" ;;
    *) die "STEAMLING_BASE_URL=${STEAMLING_BASE_URL} isn't a release of ${GH_REPO}.
Set it to ${prefix}base (or another tag name) in config/local.conf." ;;
  esac
  case "${GH_TAG}" in */*|*-next|*-prev|*-[0-9]*) die "release tag '${GH_TAG}' can't contain '/' or end in -next, -prev or -<number>" ;; esac
  gh auth status >/dev/null 2>&1 || die "gh isn't logged in: run 'gh auth login' (it needs write access to ${GH_REPO})"
  gh repo view "${GH_REPO}" >/dev/null 2>&1 || die "gh can't see ${GH_REPO}: create it on GitHub (with a README, so it has a commit) or fix STEAMLING_BASE_GITHUB"
}

# part N's tag (N=1 is the bare tag); $1 part, $2 optional suffix (-next, -prev)
gh_part_tag() { if [ "$1" -eq 1 ]; then printf '%s%s' "${GH_TAG}" "${2:-}"; else printf '%s%s-%d' "${GH_TAG}" "${2:-}" "$1"; fi; }

# The live base's id, read the way a client would (the asset, not the API).
gh_live_id() { curl -fsSL --retry 3 "${STEAMLING_BASE_URL}/SNAPSHOT_ID" 2>/dev/null | head -1 | tr -d '[:space:]'; }

# whether a release's title says it belongs to snapshot $2 ("base <id> (part ...")
gh_title_is() { case "$(gh release view "$1" --repo "${GH_REPO}" --json name --jq .name 2>/dev/null)" in "base $2 "*) return 0 ;; esac; return 1; }

gh_release_exists() { gh release view "$1" --repo "${GH_REPO}" >/dev/null 2>&1; }

# "name size" for every file a release holds
gh_assets() { gh release view "$1" --repo "${GH_REPO}" --json assets --jq '.assets[] | "\(.name) \(.size)"'; }

# the tags of every release in the repo
gh_tags() { gh release list --repo "${GH_REPO}" --limit 1000 --json tagName --jq '.[].tagName'; }

# Renaming a release onto a tag that doesn't exist yet relies on GitHub making it; make it ourselves.
gh_ensure_tag() {
  gh api "repos/${GH_REPO}/git/ref/tags/$1" >/dev/null 2>&1 && return 0
  local branch sha
  branch="$(gh repo view "${GH_REPO}" --json defaultBranchRef --jq .defaultBranchRef.name)" \
    && sha="$(gh api "repos/${GH_REPO}/commits/${branch}" --jq .sha)" \
    || die "couldn't read ${GH_REPO}'s default branch (does it have a commit?)"
  gh api "repos/${GH_REPO}/git/refs" -f ref="refs/tags/$1" -f sha="${sha}" >/dev/null || die "couldn't create tag $1 on ${GH_REPO}"
}

gh_rename_release() {  # $1 tag, $2 new tag, $3 optional new title
  gh_ensure_tag "$2"
  gh release edit "$1" --repo "${GH_REPO}" --tag "$2" ${3:+--title "$3"} >/dev/null \
    || die "couldn't rename release $1 to $2; finish the swap by hand with gh release edit"
}

gh_ensure_release() {  # $1 tag, $2 title
  gh_release_exists "$1" && return 0
  gh release create "$1" --repo "${GH_REPO}" --title "$2" --latest=false --prerelease \
    --notes "Steamling's frozen Arch Linux ARM base. pacman reads these files; there is nothing to download by hand." \
    >/dev/null || die "couldn't create release $1 on ${GH_REPO}"
}

# Upload the files given whose name and size the release doesn't already have, in batches, so an
# interrupted run picks up where it stopped. $1 tag, then paths.
gh_upload_missing() {
  local tag="$1"; shift
  declare -A have=()
  local n s f todo=()
  while read -r n s; do [ -n "${n}" ] && have["${n}"]="${s}"; done < <(gh_assets "${tag}")
  for f in "$@"; do
    [ "${have[$(basename "${f}")]:-}" = "$(stat -Lc %s "${f}")" ] || todo+=("${f}")
  done
  [ "${#todo[@]}" -gt 0 ] || return 0
  log "uploading ${#todo[@]} file(s) to ${GH_REPO} release ${tag}"
  local i
  for ((i = 0; i < ${#todo[@]}; i += 50)); do
    gh release upload "${tag}" --repo "${GH_REPO}" --clobber "${todo[@]:i:50}" >/dev/null \
      || die "upload to ${tag} failed; run the same command again to carry on"
  done
}

# How many parts a set of packages needs ($1 = number of packages; each comes with a .sig).
gh_parts_for() { local files=$(( $1 * 2 + 8 )); printf '%d' $(( (files + GH_PART_CAP - 1) / GH_PART_CAP )); }

# Publish a fresh cut. $1 snapshot dir, $2 id, $3 repo name, $4 dated tarball name.
# Prints nothing; sets GH_PARTS for the caller to pin.
gh_publish_cut() {
  local out="$1" id="$2" repo="$3" tarball="$4"
  local pkgs=() p
  for p in "${out}"/*.pkg.tar.*; do case "${p}" in *.sig) ;; *) pkgs+=("${p}") ;; esac; done
  [ "${#pkgs[@]}" -gt 0 ] || die "no packages in ${out}"
  GH_PARTS="$(gh_parts_for "${#pkgs[@]}")"

  if [ "$(gh_live_id)" = "${id}" ]; then
    warn "the live base on ${GH_REPO} is already snapshot ${id}; nothing to publish"
    return 0
  fi

  # Contiguous runs of the sorted package list, the same size each, a package and its .sig together.
  local per=$(( (${#pkgs[@]} + GH_PARTS - 1) / GH_PARTS )) part tag files
  for ((part = 1; part <= GH_PARTS; part++)); do
    gh_title_is "$(gh_part_tag "${part}")" "${id}" && continue   # went live before an interruption
    tag="$(gh_part_tag "${part}" -next)"
    gh_ensure_release "${tag}" "base ${id} (part ${part} of ${GH_PARTS}, staging)"
    files=()
    for p in "${pkgs[@]:$(( (part - 1) * per )):per}"; do files+=("${p}" "${p}.sig"); done
    gh_upload_missing "${tag}" "${files[@]}"
  done
  # the tarball, then the db, lockfile and id last, as on R2
  tag="$(gh_part_tag 1 -next)"
  gh_release_exists "${tag}" || gh_ensure_release "${tag}" "base ${id} (part 1 of ${GH_PARTS}, staging)"
  gh_upload_missing "${tag}" "${out}/${tarball}"
  gh_upload_missing "${tag}" "${out}/${repo}.db" "${out}/${repo}.db.tar.gz" \
    "${out}/${repo}.files" "${out}/${repo}.files.tar.gz" "${out}/steamling-base.lock"
  gh_upload_missing "${tag}" "${out}/SNAPSHOT_ID"

  # The swap, written so a run that dies halfway can simply be run again. A live part whose title
  # names another id is the outgoing base: it becomes -prev. The old -prev is deleted only while the
  # first live part is still there and still old, i.e. before any renaming started, and that part is
  # renamed first. The staging parts then go live with the first part last, since its SNAPSHOT_ID is
  # what marks the publish finished.
  log "swapping base ${id} in: ${GH_TAG}* -> ${GH_TAG}-prev*, ${GH_TAG}-next* -> ${GH_TAG}*"
  local t live=()
  while read -r t; do
    case "${t}" in "${GH_TAG}-"[0-9]*) live+=("${t}") ;; esac
  done < <(gh_tags)
  if gh_release_exists "${GH_TAG}" && ! gh_title_is "${GH_TAG}" "${id}"; then
    while read -r t; do
      case "${t}" in "${GH_TAG}-prev"|"${GH_TAG}-prev-"[0-9]*)
        gh release delete "${t}" --repo "${GH_REPO}" --yes --cleanup-tag >/dev/null || die "couldn't delete ${t}" ;;
      esac
    done < <(gh_tags)
    gh_rename_release "${GH_TAG}" "${GH_TAG}-prev"
  fi
  for t in ${live[@]+"${live[@]}"}; do
    gh_title_is "${t}" "${id}" || gh_rename_release "${t}" "${GH_TAG}-prev${t#"${GH_TAG}"}"
  done
  for ((part = GH_PARTS; part >= 1; part--)); do
    gh_release_exists "$(gh_part_tag "${part}" -next)" || continue
    gh_rename_release "$(gh_part_tag "${part}" -next)" "$(gh_part_tag "${part}")" "base ${id} (part ${part} of ${GH_PARTS})"
  done
  [ "$(gh_live_id)" = "${id}" ] || warn "${STEAMLING_BASE_URL}/SNAPSHOT_ID doesn't say ${id} yet (GitHub can take a minute)"
}

# Add packages to the live base without a cut. $1 snapshot dir holding the new packages and the
# rebuilt db, $2 repo name, then the new package file names.
gh_publish_extension() {
  local out="$1" repo="$2"; shift 2
  local parts="${STEAMLING_BASE_PARTS:-1}" part tag count best="" room=0 left
  for ((part = 1; part <= parts; part++)); do
    tag="$(gh_part_tag "${part}")"
    count="$(gh_assets "${tag}" | grep -c . || true)"
    left=$(( GH_ASSET_LIMIT - count ))
    [ "${left}" -gt "${room}" ] && { room="${left}"; best="${tag}"; }
  done
  [ "$(( $# * 2 ))" -le "${room}" ] \
    || die "no part of the base has room for $(( $# * 2 )) more files (the emptiest has ${room}); cut a new base instead"
  local files=() f
  for f in "$@"; do files+=("${out}/${f}" "${out}/${f}.sig"); done
  gh_upload_missing "${best}" "${files[@]}"
  # packages before the db, SNAPSHOT_ID last: the next run keys on it
  gh_upload_missing "$(gh_part_tag 1)" "${out}/${repo}.db" "${out}/${repo}.db.tar.gz" \
    "${out}/${repo}.files" "${out}/${repo}.files.tar.gz" "${out}/steamling-base.lock"
  gh_upload_missing "$(gh_part_tag 1)" "${out}/SNAPSHOT_ID"
}
