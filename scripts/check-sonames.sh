#!/bin/bash
# check-sonames.sh <rootfs> - catch a package built against a library version the image doesn't
# have. The case it exists for: a repo rebuilds a library with a new soname (libPlasma.so.7 ->
# .so.8) but not everything linked to it, so the stale package installs fine and only fails when
# something loads it. A needed soname that is missing while another version of the same library is
# installed fails the build. One with no version installed at all fails it too when one of our
# own packages needs it, and is only reported for anyone else's (an optional dependency left out).
set -euo pipefail
root="${1:?usage: check-sonames.sh <rootfs>}"
command -v readelf >/dev/null || { echo "check-sonames: readelf not found (binutils)" >&2; exit 2; }

# The loader's search path, as the image will see it.
libdirs=(/usr/lib)
for conf in "${root}/etc/ld.so.conf" "${root}"/etc/ld.so.conf.d/*.conf; do
  [ -f "${conf}" ] || continue
  while read -r d _; do
    case "${d}" in /*) libdirs+=("${d}") ;; esac
  done < "${conf}"
done
declare -A have=()
for d in "${libdirs[@]}"; do
  [ -d "${root}${d}" ] || continue
  while IFS= read -r n; do have["${n}"]=1; done < <(ls -1 "${root}${d}")
done

# Native programs, shared libraries and Qt plugins: where a Plasma, Qt or KDE mismatch shows up.
# x86 trees (the FEX rootfs) and anything under /home are deliberately out of scope.
mapfile -t files < <(
  { find "${root}/usr/bin" -maxdepth 1 -type f
    find "${root}/usr/lib" -maxdepth 1 -type f -name '*.so*'
    find "${root}/usr/lib/qt6/plugins" "${root}/usr/lib/qt6/qml" -type f -name '*.so' 2>/dev/null
  } | LC_ALL=C sort)

stale=() absent=()
check_file() {  # <file> <needed...> (after RUNPATH dirs in rp[])
  local f="$1" n base dir ok r cand; shift
  dir="$(dirname "${f}")"
  for n in "$@"; do
    [ -n "${have[${n}]:-}" ] && continue
    [ -e "${dir}/${n}" ] && continue
    ok=0
    for r in "${rp[@]}"; do
      r="${r//\$ORIGIN/${dir#"${root}"}}"; r="${r//\$\{ORIGIN\}/${dir#"${root}"}}"
      [ -e "${root}${r}/${n}" ] && { ok=1; break; }
    done
    [ "${ok}" = 1 ] && continue
    base="${n%%.so*}.so"
    # Report the shortest match: the soname (libPlasma.so.6), not the full-version file beside it.
    cand=""
    for r in "${!have[@]}"; do
      case "${r}" in "${base}".[0-9]*) [ -z "${cand}" ] || [ "${#r}" -lt "${#cand}" ] && cand="${r}" ;; esac
    done
    if [ -n "${cand}" ]; then stale+=("${f#"${root}"}|${n}|${cand}")
    else absent+=("${f#"${root}"}|${n}"); fi
  done
}

# One readelf per batch; its output names each file before its headers.
cur="" machine="" needed=() rp=()
flush() {
  [ -n "${cur}" ] && [ "${machine}" = AArch64 ] && [ "${#needed[@]}" -gt 0 ] && check_file "${cur}" "${needed[@]}"
  cur="" machine="" needed=() rp=()
}
while IFS= read -r line; do
  case "${line}" in
    "File: "*) flush; cur="${line#File: }" ;;
    *"Machine:"*) machine="$(awk '{print $2}' <<< "${line}")" ;;
    *"(NEEDED)"*) n="${line##*[}"; needed+=("${n%]}") ;;
    *"(RUNPATH)"*|*"(RPATH)"*) r="${line##*[}"; IFS=: read -ra parts <<< "${r%]}"; rp+=("${parts[@]}") ;;
  esac
done < <(printf '%s\0' "${files[@]}" | xargs -0 -r readelf -h -d -W 2>/dev/null | sed -n 's/^File: /File: /p;/Machine:/p;/(NEEDED)/p;/(RUNPATH)/p;/(RPATH)/p')
flush

# A library missing altogether is usually an optional extra of an Arch package (iproute2's arpd
# wants libdb). In a package we build it's a bug: the build linked something left in the chroot
# by another package (Dolphin and libLLVM) without depending on it, and it won't start.
ours=() optional=()
if [ "${#absent[@]}" -gt 0 ]; then
  # Our package names: build-image.sh passes them from the local repos, since by now the image's
  # pacman.conf may no longer list [steamling]; the sync databases are the fallback.
  declare -A mine=()
  while IFS= read -r p; do [ -n "${p}" ] && mine["${p}"]=1; done \
    < <(if [ -n "${STEAMLING_OUR_PACKAGES:-}" ]; then printf '%s\n' "${STEAMLING_OUR_PACKAGES}"
        else chroot "${root}" pacman -Slq steamling steamling-shared 2>/dev/null; fi)
  for a in "${absent[@]}"; do
    o="$(chroot "${root}" pacman -Qqo "${a%%|*}" 2>/dev/null || true)"
    if [ -n "${o}" ] && [ -n "${mine[${o}]:-}" ]; then ours+=("${o}|${a}"); else optional+=("${a}"); fi
  done
fi
if [ "${#optional[@]}" -gt 0 ]; then
  echo "check-sonames: ${#optional[@]} optional-looking libraries are not installed at all (not an error):" >&2
  printf '  %s\n' "${optional[@]:0:15}" | tr '|' ' ' >&2
fi
if [ "${#ours[@]}" -gt 0 ]; then
  echo "check-sonames: one of our packages needs a library nothing in the image provides:" >&2
  for s in "${ours[@]}"; do
    IFS='|' read -r o f n <<< "${s}"
    echo "  ${o}: ${f} needs ${n}"
  done | sort -u >&2
  echo "check-sonames: add the library's package to depends=, or build without that feature" >&2
fi
if [ "${#stale[@]}" -gt 0 ]; then
  echo "check-sonames: built against a library version this image doesn't have:" >&2
  for s in "${stale[@]}"; do
    IFS='|' read -r f n c <<< "${s}"
    echo "  $(chroot "${root}" pacman -Qqo "${f}" 2>/dev/null || echo '?'): ${f} needs ${n}, the image has ${c}"
  done | sort -u >&2
  echo "check-sonames: those packages need a rebuild against what the image ships (or our own build of them)" >&2
fi
[ "${#stale[@]}" -eq 0 ] && [ "${#ours[@]}" -eq 0 ] || exit 1
echo "check-sonames: ${#files[@]} files, every needed library resolves"
