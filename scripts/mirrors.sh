#!/usr/bin/env bash
# mirrors.sh - clone what config/mirrors.list names into build/mirrors as bare repos, and fetch
# the ones already there; `file` entries are downloaded instead. Branches and tags only, never GitHub PR or GitLab MR refs. Safe to
# re-run; make clean keeps the mirrors. STEAMLING_MIRRORS_DIR moves them.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
M="${STEAMLING_MIRRORS_DIR:-${ROOT}/build/mirrors}"
mkdir -p "${M}"
fail=0

while read -r name url clone branches; do
  case "${name}" in ''|'#'*) continue ;; esac
  # A plain file (a package database, an index page): downloaded fresh each run.
  if [ "${clone}" = file ]; then
    echo "==> fetching ${name}"
    mkdir -p "$(dirname "${M}/${name}")"
    curl -fsSL --retry 3 -o "${M}/${name}.part" "${url}" && mv -f "${M}/${name}.part" "${M}/${name}" \
      || { rm -f "${M}/${name}.part"; echo "mirrors: fetch failed: ${name}" >&2; fail=1; }
    continue
  fi
  case "${clone}" in
    full)     args=() ;;
    shallow)  args=(--depth 1) ;;
    blobless) args=(--filter=blob:none) ;;
    *) echo "mirrors: ${name}: unknown clone mode '${clone}'" >&2; fail=1; continue ;;
  esac
  repo="${name%%:*}" dir="${M}/${name%%:*}"
  if [ "${repo}" = "${name}" ]; then
    remote=origin
    if [ ! -d "${dir}" ]; then
      echo "==> cloning ${repo}"
      git clone --bare ${args[@]+"${args[@]}"} "${url}" "${dir}" \
        || { echo "mirrors: clone failed: ${repo}" >&2; fail=1; continue; }
    fi
    git -C "${dir}" config remote.origin.fetch '+refs/heads/*:refs/heads/*'
    extra=()
  else
    remote="${name#*:}"
    [ -d "${dir}" ] || { echo "mirrors: ${name}: ${repo} is not cloned" >&2; fail=1; continue; }
    git -C "${dir}" remote get-url "${remote}" >/dev/null 2>&1 \
      || git -C "${dir}" remote add "${remote}" "${url}"
    git -C "${dir}" config "remote.${remote}.fetch" \
      "+refs/heads/${branches:-*}:refs/heads/${remote}/${branches:-*}"
    extra=(${args[@]+"${args[@]}"})
    [ "${clone}" = shallow ] && extra=()
  fi
  echo "==> fetching ${name}"
  git -C "${dir}" fetch --prune --tags ${extra[@]+"${extra[@]}"} "${remote}" \
    || { echo "mirrors: fetch failed: ${name}" >&2; fail=1; }
done < "${ROOT}/config/mirrors.list"

date -Iseconds > "${M}/LAST_FETCH"
echo "done: ${M}"
exit "${fail}"
