import json
from pathlib import Path

# Known-good settings per game, shown as a one-tap suggestion on the This Game tab. The shipped list
# sits next to this module; /etc/steamling/game-suggestions.json adds to it or overrides it, so an
# owner can keep their own without rebuilding. Each entry:
#   "<appid>": {"name": "...", "settings": {<game tweak keys>}, "proton": "<compat tool>",
#               "note": "why", "tested": "device, date"}
SHIPPED = Path(__file__).with_name("game-suggestions.json")
LOCAL = Path("/etc/steamling/game-suggestions.json")

# Only tweaks steamling-game-launch and the plugin understand; anything else in a file is ignored.
SETTING_KEYS = ("fexProfile", "audioLatency", "mesaVersion", "envVars", "fanMode", "lavdMode",
                "disableXalia", "touchDisabled", "gamepadType")


def _read(path):
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    games = data.get("games") if isinstance(data, dict) else None
    return games if isinstance(games, dict) else {}


def _clean(entry):
    if not isinstance(entry, dict):
        return None
    raw = entry.get("settings") if isinstance(entry.get("settings"), dict) else {}
    settings = {k: v for k, v in raw.items() if k in SETTING_KEYS and isinstance(v, (str, bool))}
    proton = entry.get("proton") if isinstance(entry.get("proton"), str) else ""
    if not settings and not proton:
        return None
    return {
        "name": str(entry.get("name") or ""),
        "settings": settings,
        "proton": proton,
        "note": str(entry.get("note") or ""),
        "tested": str(entry.get("tested") or ""),
    }


def load_suggestions(shipped=SHIPPED, local=LOCAL):
    merged = {}
    for source in (_read(shipped), _read(local)):
        for appid, entry in source.items():
            clean = _clean(entry)
            if str(appid).isdigit() and clean:
                merged[str(appid)] = clean
    return merged
