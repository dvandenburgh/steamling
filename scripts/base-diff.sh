#!/usr/bin/env bash
# base-diff.sh: vet a base snapshot before it goes live (make base-diff).
#
# Diffs the committed lockfile (HEAD) against the working-tree one a snapshot dry
# run just wrote, then prints two advisory lists:
#   1. watchlist moves (config/packages/base-watch.list) + open upstream issues
#   2. upstream bumps built within STEAMLING_FRESH_DAYS (default 3) of the snapshot:
#      regressions surface within days of a release, so fresh = hold back or wait
# Never fails the run; the call is yours. Knobs: BASE_DIFF_OLD/BASE_DIFF_NEW
# (lockfile paths), GITHUB_TOKEN (lifts the 10/min unauthenticated search limit).

source "$(dirname "$0")/lib.sh"
for t in curl python3 git; do need_tool "$t"; done

LOCK_REL="packages/shared/steamling-base-lock/steamling-base.lock"
WATCH="${CONFIG_DIR}/packages/base-watch.list"
FRESH_DAYS="${STEAMLING_FRESH_DAYS:-3}"

old="$(mktemp)"; trap 'rm -f "${old}"' EXIT
if [ -n "${BASE_DIFF_OLD:-}" ]; then cp "${BASE_DIFF_OLD}" "${old}"
else git -C "${STEAMLING_ROOT}" show "HEAD:${LOCK_REL}" > "${old}" || die "no committed ${LOCK_REL}"; fi
new="${BASE_DIFF_NEW:-${STEAMLING_ROOT}/${LOCK_REL}}"
[ -f "${new}" ] || die "no lockfile at ${new}; run a snapshot dry run first (STEAMLING_SNAPSHOT_NO_UPLOAD=1 make snapshot)"

declare -A ov nv
while read -r n v; do ov["$n"]="$v"; done < <(grep -v '^#' "${old}")
while read -r n v; do nv["$n"]="$v"; done < <(grep -v '^#' "${new}")
changed=()
for n in "${!nv[@]}"; do [ "${ov[$n]:-}" = "${nv[$n]}" ] || changed+=("$n"); done
mapfile -t changed < <(printf '%s\n' "${changed[@]}" | LC_ALL=C sort)
removed=()
for n in "${!ov[@]}"; do [ -n "${nv[$n]:-}" ] || removed+=("$n"); done
mapfile -t removed < <(printf '%s\n' "${removed[@]}" | LC_ALL=C sort | sed '/^$/d')

old_id="$(sed -n '1s/.*snapshot \([^ ]*\).*/\1/p' "${old}")"
new_id="$(sed -n '1s/.*snapshot \([^ ]*\).*/\1/p' "${new}")"
log "base ${old_id} -> ${new_id}: ${#changed[@]} changed/added, ${#removed[@]} removed"
# A package leaves the base when no build installs it any more. That is right for a layer
# that was dropped, and wrong when something still needs it but never said so: the 20261121
# base lost plasma-pa that way. Read the names, devices on the old base keep a stale copy.
if [ "${#removed[@]}" -gt 0 ]; then
  log "no longer in the base (devices that have them keep the old copy, which never updates):"
  printf '%s\n' "${removed[@]}" | fmt -w 96 | sed 's/^/    /'
fi
[ "${#changed[@]}" -gt 0 ] || [ "${#removed[@]}" -gt 0 ] || { ok "nothing moved"; exit 0; }
[ "${#changed[@]}" -gt 0 ] || exit 0

# 1:X-1 -> X: issue titles quote the upstream version, never epoch or pkgrel.
upver() { local v="${1#*:}"; printf '%s' "${v%-*}"; }

# Prints "<count>" then up to 5 "title <url>" lines; "?" on a failed or rate-limited call.
gh_search() {
  local auth=()
  [ -z "${GITHUB_TOKEN:-}" ] || auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  curl -fsSG "${auth[@]}" -H 'Accept: application/vnd.github+json' \
    --data-urlencode "q=$1" --data-urlencode per_page=5 \
    https://api.github.com/search/issues 2>/dev/null \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); print(d["total_count"])
for i in d["items"]: print("      - %s <%s>" % (i["title"][:90], i["html_url"]))' \
  || echo "?"
}

# --- 1. watchlist ------------------------------------------------------------
log "watchlist (${WATCH#"${STEAMLING_ROOT}/"})"
since="$(date -u -d "60 days ago" +%Y-%m-%d 2>/dev/null || date -u -v-60d +%Y-%m-%d)"
hits=0
while read -r pat tracker why; do
  case "${pat}" in ''|'#'*) continue ;; esac
  moved=()
  for n in "${changed[@]}"; do [[ "$n" == ${pat} ]] && moved+=("$n"); done
  [ "${#moved[@]}" -gt 0 ] || continue
  why="${why#\# }"
  hits=$((hits + 1))
  n="${moved[0]}"
  extra=""; [ "${#moved[@]}" -eq 1 ] || extra=" (+$(( ${#moved[@]} - 1 )) more ${pat})"
  printf '  %s %s -> %s%s  %s\n' "$n" "${ov[$n]:-new}" "${nv[$n]}" "${extra}" "${why}"
  if [[ "${tracker}" == http* ]]; then
    printf '    check by hand: %s\n' "${tracker}"
    continue
  fi
  ver="$(upver "${nv[$n]}")"
  { read -r c; body="$(cat)"; } < <(gh_search "repo:${tracker} is:issue is:open \"${ver}\"")
  printf '    open issues mentioning %s: %s\n' "${ver}" "$c"; [ -z "${body}" ] || printf '%s\n' "${body}"
  { read -r c; body="$(cat)"; } < <(gh_search "repo:${tracker} is:issue is:open regression created:>=${since}")
  printf '    open "regression" issues since %s: %s\n' "${since}" "$c"; [ -z "${body}" ] || printf '%s\n' "${body}"
done < "${WATCH}"
[ "${hits}" -gt 0 ] || ok "no watched package moved"

# --- 2. freshness ------------------------------------------------------------
# BUILDDATE is ALARM's build, which trails the upstream release by days at most.
db="${BUILD_DIR}/snapshot/${new_id}/${STEAMLING_OWN_BASE_REPO}.db.tar.gz"
log "built within ${FRESH_DAYS} days of the snapshot"
if [ ! -f "${db}" ]; then
  warn "no ${db#"${STEAMLING_ROOT}/"} (run in the build VM after the dry run); freshness skipped"
  exit 0
fi
# Ages count back from the snapshot (the db's mtime), so a re-run days later agrees.
fresh="$(python3 - "${db}" "${FRESH_DAYS}" <<'EOF'
import os, sys, tarfile
db, days = sys.argv[1], int(sys.argv[2])
ref = int(os.path.getmtime(db)); cutoff = ref - days * 86400
with tarfile.open(db) as t:
    for m in t.getmembers():
        if not m.name.endswith("/desc"):
            continue
        f = t.extractfile(m).read().decode().split("\n\n")
        kv = {b.split("\n")[0]: b.split("\n")[1] for b in f if b.startswith("%")}
        bd = int(kv["%BUILDDATE%"])
        if bd >= cutoff:
            print(kv["%NAME%"], (ref - bd) // 86400)
EOF
)"
n_fresh=0
while read -r n age; do
  [ -n "$n" ] && [ "${ov[$n]:-}" != "${nv[$n]:-}" ] || continue
  # A pkgrel-only rebuild ships the same upstream code; only new releases carry regressions.
  [ -z "${ov[$n]:-}" ] || [ "$(upver "${ov[$n]}")" != "$(upver "${nv[$n]}")" ] || continue
  printf '  %-32s %s -> %s  (%sd old)\n' "$n" "${ov[$n]:-new}" "${nv[$n]}" "${age}"
  n_fresh=$((n_fresh + 1))
done < <(printf '%s\n' "${fresh}" | LC_ALL=C sort)
[ "${n_fresh}" -gt 0 ] || ok "nothing fresh"
[ "${n_fresh}" -eq 0 ] || warn "${n_fresh} fresh package(s): skim them; hold back via the last-good repo"
