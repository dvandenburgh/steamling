#!/usr/bin/env bash
# stage-check.sh — consistency gate on a staged repo, run by make stage
# (re-run alone: make stage-check / stage-check-shared). Per SoC:
#   resolve  every depends= of every staged package is satisfiable
#   reach    every staged name is in a layer/device meta's closure (NEW names FAIL);
#            a hard dep in that closure nothing provides FAILs too
#   rename   every DROP='d name is replaces='d by something still published
#   version  a swapped package is strictly newer than the live one
#   shadow   a per-SoC copy of a shared name is not older than [steamling-shared]
#   order    no device can still hold a version a staged conflicts= range excludes
# STEAMLING_STAGE_CHECK_OFFLINE=1 reuses the last downloaded dbs. A FAIL withdraws .staged-ok.

source "$(dirname "$0")/lib.sh"
for t in bsdtar vercmp rclone; do need_tool "$t"; done
shopt -s nullglob

STAGE="${REPO_STAGE_DIR}"
MARKER="${STAGE}/.staged-ok"
DBCACHE="${BUILD_DIR}/stage/.dbcache"
[ -d "${STAGE}" ] || die "no staged tree at ${STAGE} — run 'make stage' first"
mkdir -p "${DBCACHE}"
tmp="$(mktemp -d)"; trap 'rm -rf "${tmp}"' EXIT

fail=0; warned=0
FAIL() { printf '  %sFAIL%s %s\n' "$_c_red" "$_c_rst" "$*"; fail=1; }
WARN() { printf '  %swarn%s %s\n' "$_c_yel" "$_c_rst" "$*"; warned=1; }
note() { printf '  %-10s %s\n' "$1" "$2"; }

# kernel.conf marks a SoC dir; kernel/common holds shared patches, not a SoC.
mapfile -t ALL_SOCS < <(for d in "${STEAMLING_ROOT}"/kernel/*/kernel.conf; do basename "${d%/kernel.conf}"; done)

# --- metadata -> flat facts --------------------------------------------------
# P repo name ver | D depspec | V provides | R replaces | C conflicts | O optdep;
# keyed by repo so a name published in several repos keeps each copy.
facts="${tmp}/facts"; : > "${facts}"

pkginfo_facts() {  # $1 repo tag, $2 pkg file
  bsdtar -xOqf "$2" .PKGINFO 2>/dev/null | awk -v repo="$1" -F' = ' '
    $1=="pkgname"   {n=$2} $1=="pkgver" {v=$2}
    $1=="depend"    {d[++nd]=$2}  $1=="provides" {p[++np]=$2}
    $1=="replaces"  {r[++nr]=$2}  $1=="conflict" {c[++nc]=$2}
    $1=="optdepend" {o[++no]=$2}
    END { if (n=="") exit 1
          print "P", repo, n, v
          for (i=1;i<=nd;i++) print "D", repo, n, d[i]
          for (i=1;i<=np;i++) print "V", repo, n, p[i]
          for (i=1;i<=nr;i++) print "R", repo, n, r[i]
          for (i=1;i<=nc;i++) print "C", repo, n, c[i]
          for (i=1;i<=no;i++) { sub(/:.*/, "", o[i]); print "O", repo, n, o[i] } }'
}

db_facts() {  # $1 repo tag, $2 db file (tar of <name>-<ver>/desc)
  local d="${tmp}/db-$1"; mkdir -p "${d}"
  bsdtar -xf "$2" -C "${d}" 2>/dev/null || die "cannot read db $2"
  for f in "${d}"/*/desc; do cat "${f}"; echo '%END%'; done | awk -v repo="$1" '
    /^%[A-Z]+%$/ { sec=$0; if (sec!="%END%") next }
    sec=="%END%" { print "P", repo, n, v
                   for (i=1;i<=nd;i++) print "D", repo, n, d[i]
                   for (i=1;i<=np;i++) print "V", repo, n, p[i]
                   for (i=1;i<=nr;i++) print "R", repo, n, r[i]
                   for (i=1;i<=nc;i++) print "C", repo, n, c[i]
                   for (i=1;i<=no;i++) { sub(/:.*/, "", o[i]); print "O", repo, n, o[i] }
                   n=v=""; nd=np=nr=nc=no=0; sec=""; next }
    /^$/ { next }
    sec=="%NAME%"      {n=$0}       sec=="%VERSION%"  {v=$0}
    sec=="%DEPENDS%"   {d[++nd]=$0} sec=="%PROVIDES%" {p[++np]=$0}
    sec=="%REPLACES%"  {r[++nr]=$0} sec=="%CONFLICTS%"{c[++nc]=$0}
    sec=="%OPTDEPENDS%"{o[++no]=$0}'
}

fetch_db() {  # $1 repo tag, $2 rclone source path; returns 1 when that tree has no db
  local dst="${DBCACHE}/$1.db"
  if [ "${STEAMLING_STAGE_CHECK_OFFLINE:-0}" = "1" ] && [ -f "${dst}" ]; then
    note "db: $1" "cached (offline)"; return
  fi
  # rclone, not https: the CDN can still serve the db from before a publish
  # made seconds ago (shared publish -> per-SoC stage is one flow).
  rm -f "${dst}"
  rclone copyto "$2" "${dst}" 2>/dev/null || die "cannot fetch $1 db from $2 (rclone failed: remote or credentials)"
  # rclone exits 0 for a missing source and writes nothing: that is the "never published" case.
  [ -f "${dst}" ] || return 1
  note "db: $1" "fetched"
}

log "stage-check: ${REPO_NAME} (${REPO_SEG}) at ${STAGE#"${STEAMLING_ROOT}"/}"

nstaged=0
for f in "${STAGE}"/*.pkg.tar.*; do
  [[ "$f" == *.sig ]] && continue
  pkginfo_facts stage "$f" >> "${facts}" || die "no .PKGINFO in $(basename "$f")"
  nstaged=$((nstaged + 1))
done
[ "${nstaged}" -gt 0 ] || die "no packages in ${STAGE}"
note "staged" "${nstaged} packages"

# Every live repo whatever the scope: reach is judged fleet-wide.
fetch_db base "${STEAMLING_BASE_RCLONE_REMOTE}/pocknix-base.db" || die "no base db at ${STEAMLING_BASE_RCLONE_REMOTE}"
db_facts base "${DBCACHE}/base.db" >> "${facts}"
fetch_db shared "${STEAMLING_REPO_RCLONE_REMOTE}/shared/steamling-shared.db" || die "no [steamling-shared] db (first publish? STEAMLING_STAGE_CHECK_OFFLINE=1 with a cached copy)"
db_facts shared "${DBCACHE}/shared.db" >> "${facts}"
# A SoC added in kernel/ before its tree is first published has no db yet: skip it so it does
# not block every other SoC's release. The tree being staged must exist.
LIVE_SOCS=()
for s in "${ALL_SOCS[@]}"; do
  if ! fetch_db "${s}" "${STEAMLING_REPO_RCLONE_REMOTE}/${s}/steamling.db"; then
    if [ "${STEAMLING_REPO_SCOPE}" != "shared" ] && [ "$s" = "${SOC}" ]; then
      die "no ${s} db at ${STEAMLING_REPO_RCLONE_REMOTE}/${s} (first publish of that tree? seed it first)"
    fi
    WARN "${s}: no live tree yet (never published), left out of resolve/reach"
    continue
  fi
  db_facts "${s}" "${DBCACHE}/${s}.db" >> "${facts}"
  LIVE_SOCS+=("${s}")
done
[ "${#LIVE_SOCS[@]}" -gt 0 ] || die "no per-SoC tree is published: nothing to check reach against"

# --- load facts --------------------------------------------------------------
declare -A ver deps repl confl optd          # keyed "name@repo"
declare -A cands provs                       # name -> "repo ..." / provspec-name -> "repo:pkg:pver ..."
declare -A staged                            # name -> 1
while read -r kind repo name rest; do
  k="${name}@${repo}"
  case "${kind}" in
    P) ver["${k}"]="${rest}"; cands["${name}"]+="${repo} "
       [ "${repo}" = stage ] && staged["${name}"]=1 ;;
    D) deps["${k}"]+="${rest}"$'\n' ;;
    O) optd["${k}"]+="${rest}"$'\n' ;;
    R) repl["${k}"]+="${rest}"$'\n' ;;
    C) confl["${k}"]+="${rest}"$'\n' ;;
    V) pn="${rest%%[<>=]*}"; pv="${rest#"${pn}"}"; pv="${pv#=}"
       provs["${pn}"]+="${repo}:${name}:${pv:--} " ;;
  esac
done < "${facts}"

# --- resolution (pacman semantics) -------------------------------------------
# UNIVERSE = repos in pacman.conf order; the first repo that has a name wins.
# vercmp treats a missing pkgrel as a wildcard, like pacman's dep matching.
vercheck() {  # $1 have, $2 op, $3 want
  local r; r="$(vercmp "$1" "$3")"
  case "$2" in
    '>=') [ "$r" -ge 0 ] ;; '<=') [ "$r" -le 0 ] ;; '=') [ "$r" -eq 0 ] ;;
    '>')  [ "$r" -gt 0 ] ;; '<')  [ "$r" -lt 0 ] ;; *) return 1 ;;
  esac
}

# satisfier: sets SAT="name@repo" for the package satisfying $1 in ${UNIVERSE}
declare -A memo
satisfier() {
  local key="${UNIVERSE}|$1"
  if [ -n "${memo["${key}"]+x}" ]; then SAT="${memo["${key}"]}"; [ -n "${SAT}" ]; return; fi
  local spec="$1" name op want r c rest pv; SAT=""
  name="${spec%%[<>=]*}"; r="${spec#"${name}"}"
  op="${r%%[!<>=]*}"; want="${r#"${op}"}"
  for r in ${UNIVERSE}; do
    for c in ${cands["${name}"]:-}; do
      [ "$c" = "$r" ] || continue
      if [ -z "${op}" ] || vercheck "${ver["${name}@${r}"]}" "${op}" "${want}"; then
        SAT="${name}@${r}"; break 2
      fi
    done
  done
  if [ -z "${SAT}" ]; then
    for r in ${UNIVERSE}; do
      for c in ${provs["${name}"]:-}; do
        [ "${c%%:*}" = "$r" ] || continue
        rest="${c#*:}"; pv="${rest#*:}"
        if [ -z "${op}" ] || { [ "${pv}" != "-" ] && vercheck "${pv}" "${op}" "${want}"; }; then
          SAT="${rest%%:*}@$r"; break 2
        fi
      done
    done
  fi
  memo["${key}"]="${SAT}"; [ -n "${SAT}" ]
}

first_copy() {  # $1 name -> FC="name@repo" of the copy pacman would install
  local r; FC=""
  for r in ${UNIVERSE}; do
    [ -n "${ver["$1@${r}"]+x}" ] && { FC="$1@$r"; return 0; }
  done; return 1
}

# --- delta (from the staging marker) -----------------------------------------
pkgbase() { local b="${1##*/}"; b="${b%-*}"; b="${b%-*}"; b="${b%-*}"; printf '%s' "${b}"; }
pkgver_of() { local b="${1##*/}"; b="${b%-*}"; b="${b#"$(pkgbase "$1")-"}"; printf '%s' "${b}"; }
declare -A added=() dropped=()   # name -> version (as staged / as was live)
if [ -f "${MARKER}" ]; then
  while IFS= read -r l; do
    f="${l#[+-]}"; [ -n "${f}" ] && [ "${f}" != "${l}" ] || continue
    case "${l}" in
      +*) added["$(pkgbase "$f")"]="$(pkgver_of "$f")" ;;
      -*) dropped["$(pkgbase "$f")"]="$(pkgver_of "$f")" ;;
    esac
  done < "${MARKER}"
  note "delta" "+${#added[@]} -${#dropped[@]} (from .staged-ok)"
else
  WARN "no .staged-ok marker — version/rename checks skipped (tree-wide checks only)"
fi

# --- per-SoC checks ----------------------------------------------------------
# The staged tree stands in for its live counterpart: scope soc -> "stage shared
# base" on our SoC, "<soc> shared base" elsewhere; scope shared -> "<soc> stage base".
universe_for() {
  if [ "${STEAMLING_REPO_SCOPE}" = "shared" ]; then printf '%s stage base' "$1"
  elif [ "$1" = "${SOC}" ]; then printf 'stage shared base'
  else printf '%s shared base' "$1"; fi
}
ROOTS=(steamling-core steamling-steam-full steamling-desktop-full steamling-emulation-full)

check_resolve() {  # $1 soc
  UNIVERSE="$(universe_for "$1")"
  log "resolve as a $1 device (repo order: ${UNIVERSE// / > })"
  local n spec
  for n in "${!staged[@]}"; do
    while IFS= read -r spec; do
      [ -n "${spec}" ] || continue
      satisfier "${spec}" || FAIL "${n}: depends on '${spec}' — nothing in ${UNIVERSE// /, } provides it"
    done <<< "${deps["${n}@stage"]:-}"
  done
}

declare -A reached   # name -> soc list it is reached on
check_reach() {  # $1 soc: BFS over depends + optdepends from the roots
  UNIVERSE="$(universe_for "$1")"
  local -A seen; local queue=() k spec n root kind edges
  for root in "${ROOTS[@]}" "steamling-device-$1"; do
    if first_copy "${root}"; then seen["${root}"]=1; queue+=("${FC}")
    else WARN "$1: root ${root} is not published anywhere in ${UNIVERSE// /, }"; fi
  done
  while [ "${#queue[@]}" -gt 0 ]; do
    k="${queue[0]}"; queue=("${queue[@]:1}")
    for kind in D O; do
      if [ "${kind}" = D ]; then edges="${deps["${k}"]:-}"; else edges="${optd["${k}"]:-}"; fi
      while IFS= read -r spec; do
        [ -n "${spec}" ] || continue
        if ! satisfier "${spec}"; then
          # a hard dep nothing provides = a member a failed build never published; base internals are ALARM's
          [ "${kind}" = D ] && [ "${k#*@}" != base ] && \
            FAIL "$1: ${k%@*} (${k#*@}) depends on '${spec}' — nothing in ${UNIVERSE// /, } provides it"
          continue
        fi
        n="${SAT%@*}"
        [ -n "${seen["${n}"]+x}" ] && continue
        seen["${n}"]=1; first_copy "${n}" && queue+=("${FC}")
      done <<< "${edges}"
    done
  done
  for n in "${!seen[@]}"; do reached["${n}"]+="$1 "; done
}

check_shadow() {  # $1 soc: an older per-SoC copy hides the newer shared one
  local soc_repo shared_repo n r
  if [ "${STEAMLING_REPO_SCOPE}" = "shared" ]; then soc_repo="$1"; shared_repo=stage
  else soc_repo=stage; shared_repo=shared; fi
  for n in "${!cands[@]}"; do
    [ -n "${ver["${n}@${soc_repo}"]+x}" ] && [ -n "${ver["${n}@${shared_repo}"]+x}" ] || continue
    r="$(vercmp "${ver["${n}@${soc_repo}"]}" "${ver["${n}@${shared_repo}"]}")"
    [ "$r" -ge 0 ] && continue
    if [ "${soc_repo}" = stage ]; then
      FAIL "${n}: staged ${ver["${n}@stage"]} is OLDER than [steamling-shared] ${ver["${n}@shared"]} and would shadow it on $1"
    else
      WARN "${n}: [steamling] $1 still has ${ver["${n}@$1"]} which shadows the staged shared ${ver["${n}@stage"]} — DROP it there"
    fi
  done
}

for s in "${LIVE_SOCS[@]}"; do
  if [ "${STEAMLING_REPO_SCOPE}" = "shared" ] || [ "$s" = "${SOC}" ]; then
    check_resolve "$s"; check_shadow "$s"
  fi
  check_reach "$s"
done

log "reach (roots: ${ROOTS[*]} steamling-device-<soc>)"
for n in "${!staged[@]}"; do
  [ -n "${reached["${n}"]+x}" ] && continue
  # replaces= is a delivery edge both ways: replacing a reached name rides in
  # on it; being replaced by something published means it needs no root.
  via=""
  while IFS= read -r spec; do
    [ -n "${spec}" ] || continue
    spec="${spec%%[<>=]*}"
    if [ -n "${reached["${spec}"]+x}" ] || [ -n "${ver["${spec}@base"]+x}" ]; then via="replaces=${spec}"; break; fi
  done <<< "${repl["${n}@stage"]:-}"
  if [ -z "${via}" ]; then
    for k in "${!repl[@]}"; do
      while IFS= read -r spec; do
        [ "${spec%%[<>=]*}" = "${n}" ] && { via="replaced by ${k%@*} (${k#*@})"; break 2; }
      done <<< "${repl["${k}"]}"
    done
  fi
  if [ -n "${via}" ]; then
    note "reach" "${n}: ${via}"
  elif [ -n "${added["${n}"]+x}" ] && [ -z "${dropped["${n}"]+x}" ]; then
    FAIL "${n}: NEW name that no root depends on — fielded devices will never install it (add a dep edge to a layer/device meta)"
  else
    WARN "${n}: no root reaches it — installed devices keep updating it by name, fresh installs never get it"
  fi
done

# --- delta checks (scope-independent) ----------------------------------------
if [ -f "${MARKER}" ]; then
  log "checking the delta vs live"
  for n in "${!added[@]}"; do
    [ -n "${dropped["${n}"]+x}" ] || continue
    r="$(vercmp "${added["${n}"]}" "${dropped["${n}"]}")"
    [ "$r" -gt 0 ] || FAIL "${n}: staged ${added["${n}"]} is not newer than live ${dropped["${n}"]} — pacman never downgrades on -Syu"
  done
  for n in "${!dropped[@]}"; do
    [ -n "${added["${n}"]+x}" ] && continue
    if [ "${STEAMLING_REPO_SCOPE}" != "shared" ] && [ -n "${ver["${n}@shared"]+x}" ]; then
      note "moved" "${n} -> [steamling-shared] ${ver["${n}@shared"]}"; continue
    fi
    who=""; has_conflict=0
    for k in "${!repl[@]}"; do
      while IFS= read -r spec; do
        [ "${spec%%[<>=]*}" = "${n}" ] || continue
        who="${k}"
        case "${confl["${k}"]:-}" in *"${n}"*) has_conflict=1 ;; esac
      done <<< "${repl["${k}"]}"
    done
    if [ -z "${who}" ]; then
      FAIL "${n}: dropped from live but nothing published has replaces=${n} — installed devices keep the orphan forever"
    else
      note "rename" "${n} -> ${who%@*} (replaces=)"
      [ "${has_conflict}" -eq 1 ] || WARN "${who%@*}: replaces=${n} without conflicts=${n} — pacman may refuse the swap on file collisions"
    fi
  done
fi

# --- publish order for versioned conflicts= ----------------------------------
# A device that -Syu's the conflicter while it still holds X in the range gets a conflict prompt
# that --noconfirm refuses, so every live SoC that sees this stage must already serve X past the
# range. A <name>-<soc> package its own live tree no longer serves stays on its devices; any
# other absent name is one we never ship. Unversioned entries are mutual exclusion, not order.
log "publish order (versioned conflicts=)"
if [ "${STEAMLING_REPO_SCOPE}" = "shared" ]; then order_socs=("${LIVE_SOCS[@]}"); else order_socs=("${SOC}"); fi
for n in "${!staged[@]}"; do
  while IFS= read -r spec; do
    x="${spec%%[<>=]*}"; r="${spec#"${x}"}"; op="${r%%[!<>=]*}"; want="${r#"${op}"}"
    [ -n "${op}" ] || continue
    for s in "${order_socs[@]}"; do
      UNIVERSE="$(universe_for "${s}")"
      if first_copy "${x}"; then
        if vercheck "${ver["${FC}"]}" "${op}" "${want}"; then
          FAIL "${n}: conflicts=${spec}, but a ${s} device's -Syu still gets ${x} ${ver["${FC}"]} from [${FC#*@}]; publish ${x} past the range first"
        fi
      elif [ "${x%-"${s}"}" != "${x}" ]; then
        FAIL "${n}: conflicts=${spec}, but nothing in ${s}'s repo order serves ${x}; devices that have it keep it"
      fi
    done
  done <<< "${confl["${n}@stage"]:-}"
done

echo
if [ "${fail}" -eq 0 ]; then
  [ "${warned}" -eq 0 ] && ok "stage-check passed" || ok "stage-check passed with warnings"
else
  rm -f "${MARKER}"
  die "stage-check found problems (see FAIL lines above); fix and re-run make stage"
fi
