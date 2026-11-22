#!/usr/bin/env bash
# publish-changed.sh — publish every package this checkout built that the package repo doesn't have
# yet, in both trees (make publish-changed, or ./build.sh --update --publish). Run it as yourself.
#
# It compares build/localrepo with the live repo: a package goes up when the repo doesn't have it
# or has an older version. For those names it then does what you'd otherwise type by hand,
# make stage + make publish for this device family's [steamling] tree first, then
# make stage-shared + make publish-shared, with every check they run. A tree that fails its check
# stops there with nothing uploaded. The per-SoC tree goes first, since shared packages depend on
# per-SoC ones (steamling-steam on gamescope, say); when its check fails, the shared tree goes up
# first and the per-SoC tree is tried once more, for the other way round (a BSP needing a new
# shared package). Nothing is ever dropped from the repo here; use make stage DROP= for that.

source "$(dirname "$0")/lib.sh"
for t in curl bsdtar vercmp; do need_tool "${t}"; done
[ "$(id -u)" -ne 0 ] || die "run this as yourself, not with sudo: gh and your signing key live in your account"
[ -n "${STEAMLING_REPO_PUBLIC}" ] || die "no package repo is set up (STEAMLING_REPO_URL / STEAMLING_REPO_GITHUB in config/steamling.conf)"
S="${STEAMLING_ROOT}/scripts"
# publish-repo.sh's escape hatch publishes the raw localrepo and prunes the release to match; this
# script only ever publishes what it staged.
unset STEAMLING_PUBLISH_FROM
shopt -s nullglob

# "name version" for every package in a live db; returns 1 when the tree has never been published
live_versions() {  # $1 = release/folder (sm8550, shared), $2 = repo name
  local db rc=0
  db="$(mktemp)"
  if curl -fsSL --retry 3 -o "${db}" "${STEAMLING_REPO_PUBLIC}/$1/$2.db" 2>/dev/null; then
    bsdtar -tf "${db}" | sed -n 's|/desc$||p' | while IFS= read -r e; do
      # <name>-<pkgver>-<pkgrel>; names can hold dashes, versions can't
      printf '%s %s-%s\n' "${e%-*-*}" "$(printf '%s' "${e%-*}" | sed 's/.*-//')" "${e##*-}"
    done
  else
    rc=1
  fi
  rm -f "${db}"
  return "${rc}"
}

# the names in localrepo dir $1 that are new to, or newer than, the live packages in $2
# ("name version" lines, from live_versions)
changed_in() {
  local dir="$1" lines="$2" f b name ver live r
  declare -A have=()
  while read -r name ver; do [ -n "${name}" ] && have["${name}"]="${ver}"; done <<< "${lines}"
  for f in "${dir}"/*.pkg.tar.*; do
    case "${f}" in *.sig) continue ;; esac
    b="$(basename "${f}")"; b="${b%.pkg.tar.*}"; b="${b%-*}"       # drop .pkg.tar.* and -<arch>
    name="${b%-*-*}"; ver="${b#"${name}"-}"
    live="${have[${name}]:-}"
    if [ -z "${live}" ]; then
      printf '%s\n' "${name}"
      continue
    fi
    r="$(vercmp "${ver}" "${live}")"
    if [ "${r}" -gt 0 ]; then
      printf '%s\n' "${name}"
    elif [ "${r}" -lt 0 ]; then
      warn "${name}: the build has ${ver}, older than the repo's ${live}, so it stays as it is" >&2
    fi
  done | sort -u
}

# Stage and publish one tree. $1 = soc or shared. Returns 1 when staging (the checks) failed, with
# nothing uploaded; a failed upload stops the script.
publish_tree() {
  local dir seg repo lines names=()
  if [ "$1" = shared ]; then
    export STEAMLING_REPO_SCOPE=shared
    dir="${LOCALREPO_SHARED_DIR}" seg=shared repo=steamling-shared
  else
    unset STEAMLING_REPO_SCOPE
    dir="${LOCALREPO_DIR}" seg="${SOC}" repo=steamling
  fi
  if [ ! -d "${dir}" ]; then warn "no ${dir}: nothing built for [${repo}]"; return 0; fi
  lines="$(live_versions "${seg}" "${repo}")" \
    || die "${seg} has never been published: do its first publish by hand (docs/building/publishing.md, \"The first publish\")"
  mapfile -t names < <(changed_in "${dir}" "${lines}")
  if [ "${#names[@]}" -eq 0 ]; then
    ok "[${repo}] ${seg}: nothing newer than the repo"
    return 0
  fi
  log "[${repo}] ${seg}: publishing ${names[*]}"
  "${S}/stage-repo.sh" "${names[@]}" || return 1
  "${S}/publish-repo.sh" || die "publishing ${seg} failed; 'make publish-changed' runs it again"
  published=$((published + ${#names[@]}))
}

published=0
if ! publish_tree soc; then
  warn "the ${SOC} tree didn't pass its checks; publishing the shared tree first, in case it needs that, then trying again"
  publish_tree shared || die "staging the shared tree failed too, so nothing more was published (see the checks above)"
  publish_tree soc || die "the ${SOC} tree still doesn't pass its checks, so it wasn't published (see above)"
else
  publish_tree shared || die "staging the shared tree failed, so it wasn't published (see the checks above)"
fi
ok "${published} package(s) published"
