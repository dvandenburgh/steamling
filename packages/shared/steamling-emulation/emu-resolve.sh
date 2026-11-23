# One answer to "which binary is <emulator>" for the wrappers, steamling-play and the seeder:
# a build dropped into ~/Emulation/emulators/<name>/ wins over the packaged one.
EMU_DROP="${HOME}/Emulation/emulators"
EMU_NAMES="armsx2 eden ryujinx rpcs3 vita3k xemu dolphin cemu azahar ppsspp"

# Steam starts every shortcut with the client's LD_LIBRARY_PATH (its own bundled libraries, an
# SDL3 among them, ahead of the system's) and its overlay in LD_PRELOAD, and ES-DE hands both on
# to whatever it launches. The emulators are built against the system libraries and gain nothing
# from the overlay hooks, so they start without either.
unset LD_PRELOAD LD_LIBRARY_PATH
# An AppImage mounts itself with fusermount, and looks for it on PATH. Where the PATH Steam hands
# out has neither one, point it at the system's.
if ! command -v fusermount3 >/dev/null 2>&1 && ! command -v fusermount >/dev/null 2>&1; then
  [ -x /usr/bin/fusermount ] && export FUSERMOUNT_PROG=/usr/bin/fusermount
fi

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

# ES-DE and Steam throw away whatever an emulator prints, and that's where it says why a game
# didn't start. Each launch writes it to ~/.local/state/steamling/emulators/<name>.log instead;
# the launch before that one is kept as <name>.log.old.
emu_log() {  # $1 name, then the command line: everything this shell runs from here goes there
  local dir="${XDG_STATE_HOME:-${HOME}/.local/state}/steamling/emulators" log
  mkdir -p "${dir}" 2>/dev/null || return 0
  log="${dir}/$1.log"; shift
  [ -f "${log}" ] && mv -f "${log}" "${log}.old" 2>/dev/null
  printf '%s: %s\n' "$(date '+%F %T')" "$*" > "${log}" 2>/dev/null || return 0
  # The locale, display and driver settings it started with, since those differ between ES-DE, a Steam
  # tile and the desktop.
  env | grep -E '^(LANG|LC_|DISPLAY|WAYLAND_DISPLAY|GAMESCOPE_WAYLAND_DISPLAY|ENABLE_GAMESCOPE_WSI|VK_|MESA_|TU_|QT_|SDL_)' \
    | sort >> "${log}" 2>/dev/null
  printf -- '---\n' >> "${log}" 2>/dev/null
  exec >> "${log}" 2>&1
}

emu_missing() {  # $1 name: the user-facing "not installed" exit
  echo "steamling: $1 is not installed. Drop its AppImage into ${EMU_DROP}/$1/ (see ~/Emulation/README.txt)." >&2
  exit 1
}
