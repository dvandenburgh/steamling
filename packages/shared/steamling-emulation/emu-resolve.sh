# One answer to "which binary is <emulator>" for the wrappers, steamling-play and the seeder:
# a build dropped into ~/Emulation/emulators/<name>/ wins over the packaged one.
EMU_DROP="${HOME}/Emulation/emulators"
EMU_NAMES="armsx2 eden ryujinx rpcs3 vita3k xemu dolphin cemu azahar ppsspp"

# Steam starts every shortcut with the client's LD_LIBRARY_PATH (its own bundled libraries, an
# SDL3 among them, ahead of the system's) and its overlay in LD_PRELOAD, and ES-DE hands both on
# to whatever it launches. The emulators are built against the system libraries and gain nothing
# from the overlay hooks, so they start without either.
unset LD_PRELOAD LD_LIBRARY_PATH

# Heavy emulators pin to the board's game cores: scx_lavd otherwise parks the critical thread
# on a little core (chop + audio crackle). Unlike the game pin, a board without the key still
# pins, to the cores cores.sh guesses from capacity.
. /usr/lib/steamling/cores.sh
big_cores() { steamling_big_cores guess; }

emu_path_names() {  # $1 name -> the binary names a normal install would put on PATH
  case "$1" in
    ryujinx) echo "Ryujinx Ryujinx.Ava ryujinx" ;;
    eden)    echo "eden Eden" ;;
    armsx2)  echo "armsx2 ARMSX2" ;;
    rpcs3)   echo "rpcs3" ;;
    vita3k)  echo "Vita3K vita3k" ;;
    xemu)    echo "xemu" ;;
    *)       echo "" ;;
  esac
}

emu_path() {  # $1 name -> prints the executable, or returns 1
  local d="${EMU_DROP}/$1" f n=0 pick=""
  if [ -d "${d}" ]; then
    for f in "${d}"/*; do [ -f "${f}" ] || continue; n=$((n + 1)); pick="${f}"; done
    if [ "${n}" -eq 1 ]; then
      # browser downloads arrive without the x bit; the file is the user's own
      [ -x "${pick}" ] || chmod u+x "${pick}" 2>/dev/null
      printf '%s\n' "${pick}"; return 0
    fi
    [ "${n}" -gt 1 ] && echo "steamling: ${d} holds ${n} files, expected exactly one; using the packaged build" >&2
  fi
  case "$1" in
    armsx2)  f=/opt/steamling/emulators/armsx2/ARMSX2.AppImage ;;
    eden)    f=/opt/steamling/emulators/eden/Eden.AppImage ;;   # pre-retirement installs only
    rpcs3)   f=/opt/steamling/emulators/rpcs3/rpcs3.AppImage ;;
    vita3k)  f=/opt/steamling/emulators/vita3k/Vita3K.AppImage ;;
    xemu)    f=/opt/steamling/emulators/xemu/xemu.AppImage ;;
    dolphin) f="$(command -v dolphin-emu 2>/dev/null)" ;;
    cemu)    f="$(command -v Cemu 2>/dev/null)" ;;
    azahar)  f="$(command -v azahar 2>/dev/null)" ;;
    ppsspp)  f="$(command -v PPSSPPSDL 2>/dev/null || command -v ppsspp 2>/dev/null)" ;;
    *)       f="" ;;
  esac
  [ -n "${f}" ] && [ -x "${f}" ] && { printf '%s\n' "${f}"; return 0; }
  # Our staticpath rule shadows ES-DE's own systempath lookup, so a build the user installed
  # normally (Ryujinx from the AUR, say) is only found if we look too.
  for f in $(emu_path_names "$1"); do
    f="$(command -v "${f}" 2>/dev/null)" && [ -x "${f}" ] && { printf '%s\n' "${f}"; return 0; }
  done
  return 1
}

emu_missing() {  # $1 name: the user-facing "not installed" exit
  echo "steamling: $1 is not installed. Drop its AppImage into ${EMU_DROP}/$1/ (see ~/Emulation/README.txt)." >&2
  exit 1
}

# The handheld's own panel is DSI (eDP on a few boards); any other connected output is a TV or
# monitor, such as the Retroid dock's.
on_external_display() {
  local s c
  for s in /sys/class/drm/card*-*/status; do
    [ -r "${s}" ] || continue
    c="${s%/status}"; c="${c##*/}"
    case "${c}" in *-DSI-*|*-eDP-*|*-Writeback-*) continue ;; esac
    [ "$(cat "${s}" 2>/dev/null)" = connected ] && return 0
  done
  return 1
}

# Switch emulators start in handheld mode on the built-in screen and docked on a TV, as a real
# Switch does. Docked mode renders the TV resolution with the games' heavier TV-mode effects,
# which on the handheld's own screen mostly costs battery. ~/.config/steamling/switch-mode
# holding "handheld" or "docked" pins one instead. $1 = eden or ryujinx; writes the emulator's
# config just before it starts, so a mode picked in the emulator's own menu lasts one session.
switch_console_mode() {
  local m="" docked=false
  IFS= read -r m 2>/dev/null < "${HOME}/.config/steamling/switch-mode"
  case "${m}" in
    docked)   docked=true ;;
    handheld) docked=false ;;
    *)        on_external_display && docked=true ;;
  esac
  command -v python3 >/dev/null 2>&1 || return 0
  case "$1" in
    eden)    python3 -I - "${HOME}/.config/eden/qt-config.ini" "${docked}" <<'PY' ;;
import os, sys
path, docked = sys.argv[1], sys.argv[2] == "true"
try:
    with open(path) as f:
        lines = f.read().split("\n")
except OSError:
    lines = []
keys = ("use_docked_mode=", "use_docked_mode\\default=")
new = ["use_docked_mode\\default=false", f"use_docked_mode={1 if docked else 0}"]
out, placed = [], False
for line in lines:
    if line.strip() == "[System]" and not placed:
        out.append(line)
        out.extend(new)
        placed = True
        continue
    if placed and line.startswith(keys):
        continue
    out.append(line)
if not placed:
    if out and out[-1] != "":
        out.append("")
    out += ["[System]"] + new + [""]
os.makedirs(os.path.dirname(path), exist_ok=True)
tmp = path + ".steamling"
with open(tmp, "w") as f:
    f.write("\n".join(out))
os.replace(tmp, path)
PY
    ryujinx) python3 -I - "${HOME}/.config/Ryujinx/Config.json" "${docked}" <<'PY' ;;
import os, re, sys
path, docked = sys.argv[1], sys.argv[2]
try:
    with open(path) as f:
        text = f.read()
except OSError:
    sys.exit(0)  # first start: Ryujinx writes its own config, docked, and the next launch fixes it
new, n = re.subn(r'("docked_mode"\s*:\s*)(true|false)', r"\g<1>" + docked, text, count=1)
if n and new != text:
    tmp = path + ".steamling"
    with open(tmp, "w") as f:
        f.write(new)
    os.replace(tmp, path)
PY
  esac
  return 0
}
