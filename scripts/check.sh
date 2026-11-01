#!/usr/bin/env bash
# check.sh — sanity-check the project + (when present) the built artifacts.

source "$(dirname "$0")/lib.sh"

fail=0
note() { printf '  %-44s %s\n' "$1" "$2"; }

log "steamling preflight"

# --- host tooling ----------------------------------------------------------
for t in bash sed rsync curl tar; do
  if have "$t"; then note "host tool: $t" "ok"; else note "host tool: $t" "MISSING"; fail=1; fi
done
if [ "$(uname -s)" = "Linux" ]; then note "host os" "Linux ok"
else note "host os" "$(uname -s) (image build needs Linux)"; fi

# Image-build readiness on this host; notes only, so the preflight still passes anywhere. On a
# non-aarch64 host the kernel cross-compiles and the chroots run under qemu-user (binfmt_misc).
if [ "$(uname -s)" = "Linux" ]; then
  if [ "$(uname -m)" = "aarch64" ]; then
    note "host arch" "aarch64 (native)"
  else
    note "host arch" "$(uname -m) (kernel cross-compiles, chroots run under qemu-user)"
    cc="${CROSS_COMPILE:-aarch64-linux-gnu-}gcc"
    have "${cc}" && note "cross compiler" "${cc} ok" || note "cross compiler" "MISSING ${cc} (make kernel)"
    bf="$(grep -l '^magic 7f454c46020101.*0200b700$' /proc/sys/fs/binfmt_misc/* 2>/dev/null | head -n 1 || true)"
    if [ -z "${bf}" ]; then
      note "qemu aarch64 binfmt" "MISSING (qemu-user-static, or qemu-user-binfmt on Ubuntu 26.04+, and its binfmt registration)"
    elif ! grep -qx enabled "${bf}"; then
      note "qemu aarch64 binfmt" "${bf##*/} disabled (sudo systemctl restart systemd-binfmt)"
    elif grep -q '^flags: .*C' "${bf}"; then
      note "qemu aarch64 binfmt" "$(sed -n 's/^flags: //p' "${bf}") ok"
    else
      note "qemu aarch64 binfmt" "$(sed -n 's/^flags: //p' "${bf}") lacks C (makepkg's sudo fails in the chroot)"
    fi
  fi
  # A Windows drive under WSL (9p) or another non-POSIX fs can't hold the chroots' owners and modes.
  fs="$(stat -f -c %T "${STEAMLING_ROOT}" 2>/dev/null || true)"
  case "${fs}" in
    v9fs|9p|drvfs|fuseblk|ntfs*|vfat|msdos|exfat) note "checkout filesystem" "${fs}: build from a Linux filesystem instead" ;;
    *) note "checkout filesystem" "${fs:-?} ok" ;;
  esac
  grep -qw btrfs /proc/filesystems 2>/dev/null || PATH="${PATH}:/usr/sbin:/sbin" modprobe -n btrfs 2>/dev/null \
    && note "btrfs (make sd-image)" "ok" || note "btrfs (make sd-image)" "MISSING in this kernel"
  have ccache && note "ccache (make kernel)" "ok" \
    || note "ccache (make kernel)" "not installed (optional: kernel rebuilds recompile everything)"
fi

# --- project layout --------------------------------------------------------
for d in config config/packages scripts packages/shared packages/soc "devices/${DEVICE}"; do
  [ -d "${STEAMLING_ROOT}/${d}" ] && note "dir: ${d}/" "ok" || { note "dir: ${d}/" "MISSING"; fail=1; }
done

# --- package placement: shared/ vs soc/ -------------------------------------
# The dir names the build scope: shared/ builds once into [steamling-shared], soc/ per SoC
# gated by ./socs. A PKGBUILD elsewhere is invisible to the build, a missing or unknown gate
# silently drops a package from every repo, and a gate file in shared/ means the package
# sits in the wrong dir.
while IFS= read -r p; do
  note "package: ${p#"${STEAMLING_ROOT}"/}" "OUTSIDE shared/ and soc/: never built"; fail=1
done < <(find "${STEAMLING_ROOT}/packages" -maxdepth 3 -name PKGBUILD \
           ! -path "*/packages/shared/*" ! -path "*/packages/soc/*" 2>/dev/null)
for p in "${STEAMLING_ROOT}"/packages/soc/*/; do
  [ -d "${p}" ] || continue
  n="$(basename "${p}")"
  if [ ! -f "${p}/socs" ]; then
    note "soc pkg: ${n}" "MISSING socs file"; fail=1; continue
  fi
  read -r _socs < "${p}/socs" || true
  [ -n "${_socs}" ] || { note "soc pkg: ${n}" "empty socs file"; fail=1; continue; }
  bad=0
  # "all" = every kernel/<soc>, so a new SoC needs no socs edits; it never mixes with names.
  if [ "${_socs}" = all ]; then note "soc pkg: ${n}" "socs: all"; continue; fi
  for s in ${_socs}; do
    [ -f "${STEAMLING_ROOT}/kernel/${s}/kernel.conf" ] || { note "soc pkg: ${n}" "unknown SoC '${s}' in socs"; fail=1; bad=1; }
  done
  [ "${bad}" -eq 0 ] && note "soc pkg: ${n}" "socs: ${_socs}"
done
for p in "${STEAMLING_ROOT}"/packages/shared/*/socs; do
  [ -e "${p}" ] || continue
  note "shared pkg: $(basename "$(dirname "${p}")")" "has a socs file (shared builds are SoC-blind: move it to packages/soc/, or delete the file)"; fail=1
done

# A package we author ships under the repo's license; repackaged third-party content keeps
# its upstream license and names it in a comment on the license= line.
_lic=""
while IFS= read -r _f; do
  _l="$(grep -n '^license=' "${STEAMLING_ROOT}/${_f}" | head -1)"
  case "${_l#*:}" in "license=('GPL-2.0-or-later')"|*"#"*) continue ;; esac
  _lic="${_lic} ${_f}:${_l%%:*}"
done < <(git -C "${STEAMLING_ROOT}" grep -l -F 'url="https://github.com/dvandenburgh/steamling"' \
           -- 'packages/shared/*/PKGBUILD' 'packages/soc/*/PKGBUILD' 'devices/*/PKGBUILD')
if [ -z "${_lic}" ]; then note "package licenses" "ok"
else note "package licenses" "not GPL-2.0-or-later and no '# <third-party>' note:${_lic}"; fail=1; fi
for f in config/steamling.conf config/pacman.conf.in config/packages/base.list \
         "devices/${DEVICE}/profile.conf" "kernel/${SOC}/kernel.conf"; do
  [ -f "${STEAMLING_ROOT}/${f}" ] && note "file: ${f}" "ok" || { note "file: ${f}" "MISSING"; fail=1; }
done
note "device" "${DEVICE} (${DEVICE_PRETTY:-?}) on ${SOC}"

# Prints "<field>=<entry>" for each replaces=/conflicts= entry in PKGBUILD $1. Shared PKGBUILDs
# run nothing at top level and have no split bodies, so sourcing reads them exactly.
pkg_relations() {
  ( set +eu; . "$1" >/dev/null 2>&1
    printf 'replaces=%s\n' "${replaces[@]}"; printf 'conflicts=%s\n' "${conflicts[@]}" ) | grep -v '=$' || true
}

# Prints one problem per line: a relation in shared dir $1 with no row in allow file $2, or a
# row whose relation is gone. $1/$2 let the self-test point it at doctored copies.
check_shared_relations() {  # $1 = packages/shared dir, $2 = allow file
  local f p e r rest rows="" have=""
  while IFS= read -r r; do
    case "${r}" in ''|'#'*) continue ;; esac
    p="${r%% :: *}"; rest="${r#* :: }"; e="${rest%% :: *}"
    case "${rest}" in *' :: '?*) rows="${rows}${p} ${e}"$'\n' ;; *) echo "${2##*/}: malformed row '${r}'" ;; esac
  done < "$2"
  for f in "$1"/*/PKGBUILD; do
    p="${f%/PKGBUILD}"; p="${p##*/}"
    for e in $(pkg_relations "${f}"); do
      have="${have}${p} ${e}"$'\n'
      grep -qxF "${p} ${e}" <<< "${rows}" || echo "${p}: ${e} has no row in ${2##*/}"
    done
  done
  while read -r p e; do
    grep -qxF "${p} ${e}" <<< "${have}" || echo "${2##*/}: '${p} :: ${e}' matches no PKGBUILD entry"
  done < <(printf '%s' "${rows}")
}

# [steamling-shared] reaches every SoC's fleet in one publish, and replaces= uninstalls on -Syu, so
# each such entry in a shared package names its reason in scripts/shared-conflicts.allow.
_allow="${STEAMLING_ROOT}/scripts/shared-conflicts.allow"
_bad="$(check_shared_relations "${STEAMLING_ROOT}/packages/shared" "${_allow}" | paste -sd ';' -)"
if [ -z "${_bad}" ]; then note "shared replaces/conflicts" "ok"
else note "shared replaces/conflicts" "${_bad}"; fail=1; fi
_t="$(mktemp -d)"
mkdir -p "${_t}/stray"
printf "pkgname=stray\nreplaces=('gone'\n  # a comment\n  'old<1')\n" > "${_t}/stray/PKGBUILD"
_out="$(check_shared_relations "${_t}" "${_allow}")"
if grep -q '^stray: replaces=old<1 has no row' <<< "${_out}"; then
  note "shared replaces/conflicts self-test" "ok"
else note "shared replaces/conflicts self-test" "a shared replaces= with no allow row went unflagged"; fail=1; fi
rm -rf "${_t}"

# --- scripts executable ----------------------------------------------------
for s in build-all.sh build-status.sh sync.sh bootstrap.sh build-image.sh build-kernel.sh build-packages.sh \
         build-sd-image.sh stage-repo.sh stage-check.sh publish-repo.sh install.sh check.sh check-docs.sh render-bsp.sh; do
  [ -x "${STEAMLING_ROOT}/scripts/${s}" ] && note "exec: scripts/${s}" "ok" || { note "exec: scripts/${s}" "not +x"; fail=1; }
done

# --- steamling-perfd factory profiles ---------------------------------------
if out="$(python3 "${STEAMLING_ROOT}/scripts/check-power-profiles.py" 2>&1)"; then note "power profiles" "ok"
else note "power profiles" "BROKEN"; printf '%s\n' "${out}" | sed 's/^/    /'; fail=1; fi

# --- versions between our own packages -------------------------------------
# Renumbering a package (a pkgrel bump, a fork's .1) can strand a sibling's versioned depends= or
# pull it into a conflicts= range; pacman only says so at the rootfs step.
if out="$(python3 "${STEAMLING_ROOT}/scripts/check-pkg-versions.py" 2>&1)"; then note "package versions" "ok"
else note "package versions" "BROKEN"; printf '%s\n' "${out}" | sed 's/^/    /'; fail=1; fi

# --- code comments: no dead repo paths, provenance or ledger facts ------------
if out="$(python3 "${STEAMLING_ROOT}/scripts/check-comments.py" 2>&1)"; then note "code comments" "ok"
else note "code comments" "STALE"; printf '%s\n' "${out}" | sed 's/^/    /'; fail=1; fi

# --- branding: every image of the steamling is generated from steamling-figure.svg ----------
if out="$(python3 "${STEAMLING_ROOT}/scripts/render-branding.py" --check 2>&1)"; then note "branding images" "ok"
else note "branding images" "STALE"; printf '%s\n' "${out}" | sed 's/^/    /'; fail=1; fi

# --- SoC families: what a new SoC or board must carry (all SoCs, not just DEVICE) ----
# An unreferenced board never loads.
# devices/README.md's key table as "<key> required|optional" (the Absent column says "required"
# or what an absent key means) plus its "Env overrides" names as "<key> env". A table that stops
# parsing empties REQUIRED_KEYS, which the family-key loop below fails on.
_doc="${STEAMLING_ROOT}/devices/README.md"
_keys="$(awk -F'|' '/^\| `STEAMLING_/ { k = $2; a = $4; gsub(/^ +| +$/, "", a)
           while (match(k, /STEAMLING_[A-Z0-9_]+/)) { print substr(k, RSTART, RLENGTH), (a == "required" ? "required" : "optional"); k = substr(k, RSTART + RLENGTH) } }' "${_doc}"
         sed -n '/^Env overrides/,/^$/p' "${_doc}" | grep -oE 'STEAMLING_[A-Z0-9_]+' | sed 's/$/ env/' || true)"

# Prints "<key> <file>" for each STEAMLING_* name that device.conf consumers $@ expand but never
# assign: assigned names are the script's own state, not keys.
contract_reads() {  # $@ = consumer files
  local f k
  for f in "$@"; do
    for k in $(grep -oE '\$\{?STEAMLING_[A-Z0-9_]+' "${f}" | sed -E 's/^\$\{?//' | sort -u); do
      grep -qE "(^|[[:space:];])(export[[:space:]]+)?${k}=" "${f}" || echo "${k} ${f#"${STEAMLING_ROOT}"/}"
    done
  done
}

# Prints one problem per line: a name consumers $2.. read that the key list $1 lacks.
check_contract() {  # $1 = "<key> <kind>" lines, $2.. = consumer files
  local known="$1" k f
  shift
  contract_reads "$@" | while read -r k f; do
    grep -q "^${k} " <<< "${known}" || echo "${f} reads ${k}, which devices/README.md's key table lacks"
  done
}

# The consumers are whatever names device.conf or cores.sh, so a key a script starts reading
# must get a table row saying whether every board sets it.
mapfile -t _consumers < <(cd "${STEAMLING_ROOT}" && git grep -l -F -e /usr/lib/steamling/device.conf \
  -e /usr/lib/steamling/cores.sh -- packages devices overlay ':!*/PKGBUILD' | sed "s|^|${STEAMLING_ROOT}/|")
_bad="$(check_contract "${_keys}" "${_consumers[@]}" | paste -sd ';' -)"
if [ -z "${_bad}" ]; then note "device.conf keys vs consumers" "ok (${#_consumers[@]} consumers)"
else note "device.conf keys vs consumers" "${_bad}"; fail=1; fi
_t="$(mktemp -d)"
printf '. /usr/lib/steamling/device.conf\necho "${STEAMLING_PANEL_W:-1080} ${STEAMLING_BOGUS:-x}"\n' > "${_t}/stray"
_out="$(check_contract "${_keys}" "${_t}/stray")"
if grep -q 'reads STEAMLING_BOGUS, which' <<< "${_out}" && ! grep -q PANEL_W <<< "${_out}"; then
  note "device.conf keys self-test" "ok"
else note "device.conf keys self-test" "a consumer reading an undocumented key went unflagged"; fail=1; fi
rm -rf "${_t}"

# Lays out boards dir $1 as family $2's BSP installs it (with what scripts/render-bsp.sh renders:
# device.conf and family.conf) in a scratch dir (printed). Installed paths point into it, so
# nested sources (variant -> base -> family.conf) and the dispatcher resolve against the tree.
stage_boards() {  # $1 = boards dir, $2 = SoC
  local t r f dev="${STEAMLING_ROOT}/devices/$2"
  t="$(mktemp -d)"; r="$(mktemp -d)"
  BOOTLOADER="$(profile_get "${dev}" BOOTLOADER)" SD_FAT_LABEL="$(profile_get "${dev}" SD_FAT_LABEL)" \
    ROOT_LABEL="$(profile_get "${dev}" ROOT_LABEL)" "${STEAMLING_ROOT}/scripts/render-bsp.sh" "$1" "${r}" ||
    { rm -rf "${t}" "${r}"; return 1; }
  for f in "$1"/*.conf "${r}"/*.conf; do
    sed -e "s|/usr/lib/steamling/boards/|${t}/|g" -e "s|/proc/device-tree/model|${t}/model|g" "${f}" > "${t}/${f##*/}"
  done
  rm -rf "${r}"
  printf '%s' "${t}"
}

# Prints "<key>=<value>" for each STEAMLING_* key board $3 of family $2 resolves from boards dir $1.
board_values() {  # $1 = boards dir, $2 = SoC, $3 = board
  local t rc=0
  t="$(stage_boards "$1" "$2")" || return 1
  env -i bash -c '. "$1" >/dev/null || exit 1; for k in ${!STEAMLING_@}; do printf "%s=%s\n" "${k}" "${!k}"; done' sh "${t}/$3.conf" || rc=1
  rm -rf "${t}"
  return "${rc}"
}

# A consumer missing a key runs on its fallback, so a required key's must be the reference
# board's value and an optional key's must change nothing (0 or empty). A fallback naming
# another variable defers to it and is skipped. Allow file $3 rows ("<key> :: <reason>") are the
# exceptions; a row that matches no fallback fails, so the list only shrinks.
check_fallbacks() {  # $1 = "<key> <kind>" lines, $2 = "<key>=<value>" reference, $3 = allow file, $4.. = consumers
  local known="$1" ref="$2" allow="$3" f k v kind want r used=" "
  shift 3
  while IFS= read -r r; do
    f="${r%%:\$\{*}"; r="${r#*\$\{}"; k="${r%%:-*}"; v="${r#*:-}"; v="${v%\}}"
    kind="$(printf '%s\n' "${known}" | awk -v k="${k}" '$1 == k { print $2; exit }')"
    case "${kind}" in required|optional) ;; *) continue ;; esac
    if grep -q "^${k} :: " "${allow}"; then used="${used}${k} "; continue; fi
    if [ "${kind}" = required ]; then
      want="$(printf '%s\n' "${ref}" | sed -n "s/^${k}=//p")"
      [ "${v}" = "${want}" ] || echo "${f#"${STEAMLING_ROOT}"/}: required ${k} falls back to '${v}', the reference board has '${want}'"
    else
      case "${v}" in ''|0) ;; *) echo "${f#"${STEAMLING_ROOT}"/}: optional ${k} falls back to '${v}', not 0 or empty" ;; esac
    fi
  done < <(grep -oHE '\$\{STEAMLING_[A-Z0-9_]+:-[^${}]*\}' "$@")
  while IFS= read -r r; do
    case "${r}" in ''|'#'*) continue ;; esac
    case "${used}" in *" ${r%% :: *} "*) ;; *) echo "${allow##*/}: '${r%% :: *}' matches no fallback" ;; esac
  done < "${allow}"
}

# The reference board is the committed default image target's fallback (first models row).
_ref_soc="$(sed -nE 's/^: "\$\{DEVICE:=([a-z0-9]+)\}".*/\1/p' "${STEAMLING_ROOT}/config/steamling.conf")"
_ref_boards="${STEAMLING_ROOT}/devices/${_ref_soc}/packages/steamling-bsp-${_ref_soc}/boards"
_ref_board="$(awk '!/^[[:space:]]*(#|$)/ { print $1; exit }' "${_ref_boards}/models" 2>/dev/null || true)"
_fb_allow="${STEAMLING_ROOT}/scripts/fallbacks.allow"
if [ -z "${_ref_board}" ]; then _bad="no reference board (config/steamling.conf DEVICE default -> boards/models)"
elif ! _ref="$(board_values "${_ref_boards}" "${_ref_soc}" "${_ref_board}")"; then _bad="reference board ${_ref_board} fails to source"
else _bad="$(check_fallbacks "${_keys}" "${_ref}" "${_fb_allow}" "${_consumers[@]}" | paste -sd ';' -)"; fi
if [ -z "${_bad}" ]; then note "device.conf fallbacks" "ok (reference ${_ref_board})"
else note "device.conf fallbacks" "${_bad}"; fail=1; fi
_t="$(mktemp -d)"
printf '%s\n' 'w=${STEAMLING_PANEL_W:-1}' 'h=${STEAMLING_PANEL_H:-1920}' 'o=${STEAMLING_PANEL_OUTPUT:-DSI-9}' \
  'r=${STEAMLING_ROTATE:-${STEAMLING_DESKTOP_ROTATE:-left}}' > "${_t}/stray"
_out="$(check_fallbacks "${_keys}" $'STEAMLING_PANEL_W=1080\nSTEAMLING_PANEL_H=1920\nSTEAMLING_DESKTOP_ROTATE=left' \
          /dev/null "${_t}/stray")"
if grep -q "required STEAMLING_PANEL_W falls back to '1'" <<< "${_out}" && grep -q 'optional STEAMLING_PANEL_OUTPUT' <<< "${_out}" &&
   ! grep -qE 'PANEL_H|ROTATE' <<< "${_out}"; then note "device.conf fallbacks self-test" "ok"
else note "device.conf fallbacks self-test" "a wrong fallback went unflagged (or a right one was flagged)"; fail=1; fi
rm -rf "${_t}"

# family.conf must carry the SoC and the install-to-internal contract, and every board must
# resolve each key the table marks required from the two (the consumers fall back to RP6 values
# without one, which is wrong on any other panel or disk).
REQUIRED_FAMILY_KEYS="STEAMLING_SOC STEAMLING_INTERNAL_DISK STEAMLING_BOOT_GPT_NAME
  STEAMLING_BOOT_STYLE STEAMLING_BOOT_FAT_LABEL STEAMLING_ROOT_LABEL"
REQUIRED_KEYS="$(printf '%s\n' "${_keys}" | awk '$2 == "required" { print $1 }' | paste -sd ' ' -)"
for _k in ${REQUIRED_FAMILY_KEYS} STEAMLING_DEVICE; do
  case " ${REQUIRED_KEYS} " in *" ${_k} "*) ;;
    *) note "device.conf required keys" "${_k} is not marked required in devices/README.md"; fail=1 ;; esac
done

# Sources $2 with nothing else set; prints "<unset keys>|<STEAMLING_SOC>".
resolve_keys() {  # $1 = keys, $2 = file
  env -i bash -c '. "$1" >/dev/null || exit 1; for k in $2; do eval "[ -n \"\${${k}:-}\" ]" || printf "%s " "${k}"; done
    printf "|%s" "${STEAMLING_SOC:-}"' sh "$2" "${1//$'\n'/ }"
}

# Sources the rendered $1/device.conf as a board reporting model $2 (empty = no model file)
# and expects "<STEAMLING_DEVICE>|<STEAMLING_BOARD_UNKNOWN>" = $3, with nothing on stdout.
probe_model() {  # $1 = scratch dir, $2 = model, $3 = expected
  local got
  rm -f "$1/model"; [ -z "$2" ] || printf '%s\0' "$2" > "$1/model"
  got="$(env -i sh -c '. "$1" > "$1.out" || exit 1; printf "%s|%s" "${STEAMLING_DEVICE:-}" "${STEAMLING_BOARD_UNKNOWN:-}"' \
    sh "$1/device.conf")" || got="(fails)"
  [ "${got}" = "$3" ] || echo "device.conf: model '$2' gives ${got}, want $3"
  [ ! -s "$1/device.conf.out" ] || echo "device.conf: model '$2' prints to stdout"
}

# Prints one problem per line for a BSP's boards/; nothing means it is fine. $2 lets the
# self-test below point it at a doctored copy.
check_boards() {  # $1 = SoC, $2 = boards dir
  local soc="$1" boards="$2" t f n b m r rows="" first="" firstm="" got want ktree
  ktree="$(kernel_get "${soc}" KERNEL_TREE)"; ktree="${ktree:-${soc}}"
  for f in family.conf models; do
    [ -f "${boards}/${f}" ] || { echo "missing boards/${f}"; return; }
  done
  t="$(stage_boards "${boards}" "${soc}")" || { echo "scripts/render-bsp.sh fails for ${soc}"; return; }
  r="$(resolve_keys "${REQUIRED_FAMILY_KEYS}" "${t}/family.conf")" || echo "family.conf fails to source"
  m="${r%%|*}"; [ -z "${m}" ] || echo "family.conf lacks ${m% }"

  while read -r b m; do
    case "${b}" in ''|'#'*) continue ;; esac
    [ -n "${m}" ] || { echo "models: ${b} has no model"; continue; }
    case "${m}" in *[\"\\\$\`]*) echo "models: '${m}' would need shell quoting" ;; esac
    [ -f "${boards}/${b}.conf" ] || echo "models: '${m}' names a missing boards/${b}.conf"
    # The dispatcher matches /proc/device-tree/model verbatim, so a typo never selects its board.
    git -C "${STEAMLING_ROOT}" grep -qF -- "model = \"${m}\";" -- "kernel/${ktree}/dts" ||
      echo "models: '${m}' is the model of no dts under kernel/${ktree}/dts"
    [ -n "${first}" ] || { first="${b}"; firstm="${m}"; }
    rows="${rows}${b}|${m}"$'\n'
  done < "${boards}/models"
  for m in $(printf '%s' "${rows}" | cut -d'|' -f2- | sort | uniq -d | tr ' ' '\001'); do
    echo "models: '${m//$'\001'/ }' is listed twice"
  done
  # The fallback board is the family's reference board: the first one its README bullet names.
  want="$(sed -nE "s/^\* \*\*${soc}\*\* \([^)]*\): ([^,;(]*[^,;( ]).*/\1/p" "${STEAMLING_ROOT}/devices/README.md")"
  [ "${firstm}" = "${want}" ] ||
    echo "models: first row (the fallback) is '${firstm}', devices/README.md names '${want}' first"

  for f in "${boards}"/*.conf; do
    n="${f##*/}"; b="${n%.conf}"
    [ "${n}" = family.conf ] && continue
    # Reachable = a models row, or sourced by another board (variants source their base).
    grep -q "^${b}|" <<< "${rows}" ||
      grep -qsE "^[[:space:]]*\. /usr/lib/steamling/boards/${n//./\\.}([[:space:]]|\$)" \
        $(ls "${boards}"/*.conf | grep -v "/${n}\$") || echo "${n} is in no models row and sourced by no board"
    grep -qx "STEAMLING_DEVICE=${b}" "${f}" || echo "${n} must set STEAMLING_DEVICE=${b} itself"
    r="$(resolve_keys "${REQUIRED_KEYS}" "${t}/${n}")" || { echo "${n} fails to source"; continue; }
    m="${r%%|*}"; [ -z "${m}" ] || echo "${n} lacks ${m% }"
    [ "${r#*|}" = "${soc}" ] || echo "${n} says STEAMLING_SOC=${r#*|}"
  done

  # The rendered dispatcher: each row picks its board, anything else the first board flagged
  # unknown, and nothing reaches stdout (cores.sh sources it inside $(...)).
  if sh -n "${t}/device.conf" 2>/dev/null; then
    while IFS='|' read -r b m; do
      probe_model "${t}" "${m}" "${b}|"
    done < <(printf '%s' "${rows}")
    probe_model "${t}" "Some Unknown Board" "${first}|1"
    probe_model "${t}" "" "${first}|1"
  else
    echo "rendered device.conf is not POSIX sh"
  fi
  rm -rf "${t}"
}

# A variable as kernel/<soc>/kernel.conf resolves it, in a clean environment like profile_get.
kernel_get() {  # $1 = SoC, $2 = variable name
  env -i bash -c '. "$1" && printf "%s" "${!2:-}"' sh "${STEAMLING_ROOT}/kernel/$1/kernel.conf" "$2"
}

# Prints one problem per line for a SoC family; nothing means it is fine.
check_family() {  # $1 = SoC
  local soc="$1" dev="${STEAMLING_ROOT}/devices/$1" bsp="${STEAMLING_ROOT}/devices/$1/packages/steamling-bsp-$1"
  local f p rel
  for f in "devices/${soc}/profile.conf" "devices/${soc}/tuning.conf" "kernel/${soc}/kernel.conf"; do
    [ -f "${STEAMLING_ROOT}/${f}" ] || echo "missing ${f}"
  done
  # The shared kernel recipe takes its pkgrel from here; makepkg dies on a missing one.
  if [ -f "${STEAMLING_ROOT}/kernel/${soc}/kernel.conf" ]; then
    rel="$(kernel_get "${soc}" KERNEL_PKGREL)"
    case "${rel}" in
      # a positive integer, or one with a minor release (a fork's 3.1 over upstream's 3)
      ''|*[!0-9.]*|0*|.*|*.|*.*.*) echo "kernel/${soc}/kernel.conf KERNEL_PKGREL='${rel}' is not a positive integer or N.M" ;;
    esac
  fi
  # A SoC on a shared tree builds kernel/<tree>/, which carries everything but kernel.conf.
  if [ -f "${STEAMLING_ROOT}/kernel/${soc}/kernel.conf" ]; then
    local tree; tree="$(kernel_get "${soc}" KERNEL_TREE)"
    if [ -n "${tree}" ]; then
      for f in patches dts config/linux.aarch64.conf; do
        [ -e "${STEAMLING_ROOT}/kernel/${tree}/${f}" ] || echo "KERNEL_TREE=${tree}: kernel/${tree}/${f} missing"
      done
      # One tree, one source: every SoC on it repeats the pin, so they must agree.
      local other v
      for other in "${STEAMLING_ROOT}"/kernel/*/kernel.conf; do
        other="$(basename "$(dirname "${other}")")"
        [ "${other}" != "${soc}" ] && [ "$(kernel_get "${other}" KERNEL_TREE)" = "${tree}" ] || continue
        for v in KERNEL_VERSION KERNEL_SOURCE_SHA256; do
          [ "$(kernel_get "${soc}" "${v}")" = "$(kernel_get "${other}" "${v}")" ] \
            || echo "${v} differs from kernel/${other}/kernel.conf, which builds the same tree (${tree})"
        done
      done
    fi
  fi
  [ -f "${dev}/profile.conf" ] || return
  grep -q "^| kernel (${soc}" "${STEAMLING_ROOT}/PATCHES.md" || echo "no PATCHES.md kernel row"
  for p in DEVICE_BSP_PKG DEVICE_META_PKG; do
    [ -f "${dev}/packages/$(profile_get "${dev}" "${p}")/PKGBUILD" ] || echo "${p} has no package under devices/${soc}/packages/"
  done
  check_boards "${soc}" "${bsp}/boards"
  # The build renders the cmdline from the profile; a committed copy would be a second source.
  [ ! -e "${bsp}/root/usr/lib/steamling/kernel-cmdline" ] ||
    echo "BSP commits root/usr/lib/steamling/kernel-cmdline, which the build renders from the profile"
  # Without it the on-device boot image rebuild skips silently, leaving the old kernel booting.
  [ "$(profile_get "${dev}" BOOTLOADER)" != qcom-abl ] || grep -q 'staged/kernel-cmdline' "${bsp}/PKGBUILD" ||
    echo "qcom-abl BSP PKGBUILD does not install staged/kernel-cmdline"
}

# Either half alone is a family: a profile without a kernel dir must fail, not go unchecked.
for _soc in $(cd "${STEAMLING_ROOT}" && ls -d kernel/*/kernel.conf devices/*/profile.conf 2>/dev/null |
              cut -d/ -f2 | sort -u); do
  _bad="$(check_family "${_soc}" | paste -sd ';' -)"
  if [ -z "${_bad}" ]; then note "family: ${_soc}" "ok"; else note "family: ${_soc}" "${_bad}"; fail=1; fi
done

# HDR on these EDID-less panels needs two halves that must agree: the board's
# STEAMLING_PANEL_HDR_NITS (gamescope's target, Steam's HDR switch) and a gamescope panel profile
# in steamling-bsp-common matching its STEAMLING_DEVICE with the same max_content_light_level.
# Either half alone gives no HDR or a wrong peak, silently.
hdr_profiles() {  # prints "<device_id> <max_content_light_level> <lua>" for every profile match
  local lua n id
  for lua in "${STEAMLING_ROOT}"/packages/shared/steamling-bsp-common/*.lua; do
    n="$(sed -n 's/.*max_content_light_level *= *\([0-9][0-9]*\).*/\1/p' "${lua}" | head -1)"
    for id in $(grep -o 'device_id *== *"[^"]*"' "${lua}" | sed 's/.*"\(.*\)"/\1/'); do
      echo "${id} ${n:-0} ${lua##*/}"
    done
  done
}
check_hdr() {
  local profiles soc t b dev nits row seen=""
  profiles="$(hdr_profiles)"
  for soc in $(cd "${STEAMLING_ROOT}/devices" && ls -d */ | tr -d /); do
    [ -d "${STEAMLING_ROOT}/devices/${soc}/packages/steamling-bsp-${soc}/boards" ] || continue
    t="$(stage_boards "${STEAMLING_ROOT}/devices/${soc}/packages/steamling-bsp-${soc}/boards" "${soc}")" || continue
    for b in "${t}"/*.conf; do
      case "${b##*/}" in family.conf|device.conf) continue ;; esac
      read -r dev nits < <(env -i bash -c '. "$1" >/dev/null 2>&1; printf "%s %s\n" "${STEAMLING_DEVICE:-}" "${STEAMLING_PANEL_HDR_NITS:-0}"' sh "${b}")
      [ -n "${dev}" ] || continue
      seen="${seen} ${dev}"
      row="$(awk -v d="${dev}" '$1 == d' <<< "${profiles}" | head -1)"
      if [ "${nits:-0}" != 0 ]; then
        if [ -z "${row}" ]; then echo "${dev}: HDR_NITS=${nits} but no panel profile matches it"
        elif [ "$(cut -d' ' -f2 <<< "${row}")" != "${nits}" ]; then
          echo "${dev}: HDR_NITS=${nits}, its profile $(cut -d' ' -f3 <<< "${row}") says $(cut -d' ' -f2 <<< "${row}")"
        fi
      elif [ -n "${row}" ]; then
        echo "${dev}: profile $(cut -d' ' -f3 <<< "${row}") says HDR, but the board sets no HDR_NITS"
      fi
    done
    rm -rf "${t}"
  done
  while read -r dev _ lua; do
    [ -n "${dev}" ] || continue
    case " ${seen} " in *" ${dev} "*) ;; *) echo "${lua} matches '${dev}', which no board is" ;; esac
  done <<< "${profiles}"
}
_bad="$(check_hdr | paste -sd ';' -)"
if [ -z "${_bad}" ]; then note "HDR panel profiles" "ok"; else note "HDR panel profiles" "${_bad}"; fail=1; fi

# A board nothing selects never loads, so check_boards must flag one: a copy of a family's
# boards/ plus a stray board has to fail.
_t="$(mktemp -d)"
_bsp="${STEAMLING_ROOT}/devices/${SOC}/packages/steamling-bsp-${SOC}"
cp -R "${_bsp}/boards" "${_t}/"
printf '. /usr/lib/steamling/boards/family.conf\nSTEAMLING_DEVICE=stray\n' > "${_t}/boards/stray.conf"
_out="$(check_boards "${SOC}" "${_t}/boards")"
if grep -q '^stray.conf is in no models row' <<< "${_out}"; then
  note "board check self-test" "ok"
else note "board check self-test" "a board in no models row went unflagged"; fail=1; fi
rm -rf "${_t}"

rm -rf "${_t}"

# makepkg sees only the package dir, so each AppImage package carries its own _appimage_icon;
# a fix to one copy (the binfmt marker, a new runtime) has to reach every AppImage package.
appimage_icon_body() { sed -n '/^_appimage_icon()/,/^}/p' "$1"; }
_ref=""; _drift=""
for _f in $(grep -l '^_appimage_icon()' "${STEAMLING_ROOT}"/packages/*/*/PKGBUILD); do
  [ -n "${_ref}" ] || _ref="$(appimage_icon_body "${_f}")"
  [ "$(appimage_icon_body "${_f}")" = "${_ref}" ] || _drift="${_drift} ${_f#"${STEAMLING_ROOT}"/}"
done
_raw="$(grep -l -- '--appimage-extract' "${STEAMLING_ROOT}"/packages/*/*/PKGBUILD | xargs -r grep -L '^_appimage_icon()' || true)"
if [ -z "${_drift}${_raw}" ]; then note "AppImage _appimage_icon copies" "identical"
else note "AppImage _appimage_icon copies" "differ:${_drift}${_raw:+ (runs --appimage-extract without it: ${_raw//${STEAMLING_ROOT}\//})}"; fail=1; fi

# Governor's backend has unit tests (stdlib unittest, nothing to install); they run
# in a second or two, so every check runs them.
_plug="${STEAMLING_ROOT}/packages/shared/steamling-decky/steamling-control"
if command -v python3 >/dev/null; then
  if _out="$(cd "${_plug}" && PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -t . 2>&1)"; then
    note "Governor unit tests" "ok ($(grep -o 'Ran [0-9]* tests' <<< "${_out}" | grep -o '[0-9]*'))"
  else
    note "Governor unit tests" "FAILED"; printf '%s\n' "${_out}" | tail -20 | sed 's/^/    /'; fail=1
  fi
else
  note "Governor unit tests" "skipped (no python3)"
fi

# A device package's root/ is copied as is, so the git mode is the installed mode: a script
# committed 644 installs 644 and never runs.
_mode=""
while read -r _m _ _ _f; do
  [ "$(head -c2 "${STEAMLING_ROOT}/${_f}" 2>/dev/null)" = '#!' ] && _want=100755 || _want=100644
  [ "${_m}" = "${_want}" ] || _mode="${_mode} ${_f}"
done < <(git -C "${STEAMLING_ROOT}" ls-files -s -- 'devices/*/packages/*/root/*' | grep -v '^120000 ')
if [ -z "${_mode}" ]; then note "device root/ modes" "ok"
else note "device root/ modes" "shebang and exec bit disagree:${_mode}"; fail=1; fi

# A common-skip line that names no kernel/common patch (after a rename) would silently
# let that patch apply again.
_stale=""
for _s in "${STEAMLING_ROOT}"/kernel/*/common-skip; do
  [ -f "${_s}" ] || continue
  while IFS= read -r _p; do
    [ -f "${STEAMLING_ROOT}/kernel/common/patches/${_p}" ] || _stale="${_stale} ${_s#"${STEAMLING_ROOT}"/}:${_p}"
  done < <(sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^$/d' "${_s}")
done
if [ -z "${_stale}" ]; then note "kernel common-skip" "ok"; else note "kernel common-skip" "not in kernel/common/patches:${_stale}"; fail=1; fi

SOC_ID_RE='(^|[^a-z0-9])sm[0-9]{4}([^0-9]|$)'
# Prints one problem per line for "<path>:<line>:<text>" hits on stdin: a chip id in a code line
# (comments stripped) that no row of allow file $1 covers, or a row that matches nothing.
check_soc_ids() {  # $1 = allow file
  local r h p n t i used=" "
  local -a globs=() res=()
  while IFS= read -r r; do
    case "${r}" in ''|'#'*) continue ;; *' :: '*' :: '?*) ;; *) echo "${1##*/}: malformed row '${r}'"; continue ;; esac
    globs+=("${r%% :: *}"); r="${r#* :: }"; res+=("${r%% :: *}")
  done < "$1"
  while IFS= read -r h; do
    p="${h%%:*}"; t="${h#*:}"; n="${t%%:*}"; t="${t#*:}"
    t="$(sed -E 's/^[[:space:]]*#.*//; s/[[:space:]]#.*//' <<< "${t}")"
    grep -qiE "${SOC_ID_RE}" <<< "${t}" || continue
    for i in "${!globs[@]}"; do
      # shellcheck disable=SC2053  # the row's glob is meant to glob
      [[ "${p}" == ${globs[i]} ]] && grep -qiE -- "${res[i]}" <<< "${t}" && { used="${used}${i} "; continue 2; }
    done
    echo "${p}:${n} names a chip"
  done
  for i in "${!globs[@]}"; do
    case "${used}" in *" ${i} "*) ;; *) echo "${1##*/}: '${globs[i]} :: ${res[i]}' matches nothing" ;; esac
  done
}

# Shared code that names today's chips mishandles the next one; the chip trees, the family
# docs and packages/soc/<name>-<soc>/ are where chip names belong.
_allow="${STEAMLING_ROOT}/scripts/soc-ids.allow"
_bad="$(git -C "${STEAMLING_ROOT}" grep -n -I -i -E "${SOC_ID_RE}" -- . ':!devices/' ':!kernel/' \
          ':!PATCHES.md' ':!CONTRIBUTING.md' ':!README.md' ':!docs/' ':(exclude,glob)**/*.allow' \
          ':(exclude,glob)packages/soc/*-sm[0-9][0-9][0-9][0-9]/**' | check_soc_ids "${_allow}" | paste -sd ';' -)"
if [ -z "${_bad}" ]; then note "chip ids outside chip trees" "ok"
else note "chip ids outside chip trees" "${_bad}"; fail=1; fi
_id="sm""8750"   # split so this line is no hit itself
_out="$(printf '%s\n' "packages/shared/steamling-steam/steamling-steam:1:  [ \"\${s}\" = ${_id} ]" \
          "packages/shared/steamling-steam/steamling-steam:2:  # ${_id} probes late" | check_soc_ids "${_allow}")"
if grep -q '^packages/shared/steamling-steam/steamling-steam:1 names a chip' <<< "${_out}" && ! grep -q 'steam:2' <<< "${_out}"; then
  note "chip ids self-test" "ok"
else note "chip ids self-test" "a stray chip id in shared code went unflagged (or a comment was flagged)"; fail=1; fi

# Docs name only what the tree has; structural READMEs follow their dirs and keep no versions.
if "${STEAMLING_ROOT}/scripts/check-docs.sh"; then note "docs match the tree" "ok"
else note "docs match the tree" "see the lines above"; fail=1; fi

# --- kernel enablement present? (committed; refreshable via sync) -----------
_npatch=$(find "${KERNEL_DIR}/patches" "${STEAMLING_ROOT}/kernel/common/patches" -name '*.patch' 2>/dev/null | wc -l | tr -d ' ')
if [ "${_npatch:-0}" -gt 0 ]; then
  note "kernel: enablement (kernel/${SOC}/ + common/)" "${_npatch} patches"
else
  note "kernel: enablement (kernel/${SOC}/ + common/)" "run 'make sync'"
fi
# vendor/ is sync reference only (gitignored); no build reads it
if [ -d "${VENDOR_DIR}/rocknix-${SOC}/reference" ]; then
  note "vendor: reference" "synced"
else
  note "vendor: reference" "run 'make sync' (build host)"
fi

# --- built artifacts (only checked if they exist) --------------------------
if [ -d "${KERNEL_BUILD_DIR}/out" ]; then
  note "kernel build" "$(cat "${KERNEL_BUILD_DIR}/out/kernelrelease" 2>/dev/null || echo present)"
else
  note "kernel build" "run 'make kernel'"
fi
if [ -f "${IMAGE_DIR}/KERNEL" ]; then
  note "boot image KERNEL" "$(du -h "${IMAGE_DIR}/KERNEL" | cut -f1) (qcom-abl)"
else
  note "boot image KERNEL" "not built (make kernel)"
fi
[ -d "${ROOTFS_DIR}" ] && note "rootfs" "present"

echo
[ "$fail" -eq 0 ] && ok "preflight passed" || die "preflight found problems (see above)"
