import json
import os
import re
import threading
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

from .system import run_cmd

# One implementation for the command line and the panel (steamling-emulation owns it). It runs as
# the deck user: Syncthing is that user's service, and the saves are theirs.
SYNC = "/usr/bin/steamling-sync"
HOME = Path("/home/deck")
DEVICE_ID = re.compile(r"[A-Z2-7]{7}(-[A-Z2-7]{7}){7}")
# What steamling-sync's status reads, read here without it: the panel polls while it is open, and
# a transient unit plus a Python start per poll is a lot of work to ask Syncthing four questions.
ENABLED_LINK = HOME / ".config/systemd/user/default.target.wants/syncthing.service"
CONFIGS = (HOME / ".local/state/syncthing/config.xml", HOME / ".config/syncthing/config.xml")
FOLDER_IDS = ("steamling-saves", "steamling-states")

_lock = threading.Lock()  # on, off and accept one at a time


def _run(args, timeout):
    # Through PID 1 like every privileged op (init namespace, clean env), as the session user.
    uid = os.stat(HOME).st_uid
    proc = run_cmd(
        ["systemd-run", "--quiet", "--collect", "--wait", "--pipe", f"--uid={uid}",
         f"--setenv=XDG_RUNTIME_DIR=/run/user/{uid}", f"--setenv=HOME={HOME}", SYNC, *args],
        timeout=timeout,
    )
    if proc is None or proc.returncode != 0:
        detail = ((proc.stderr if proc else "") or "").strip()[-200:]
        raise RuntimeError(detail or "Save sync did not answer")
    try:
        return json.loads(proc.stdout or "{}")
    except ValueError as e:
        raise RuntimeError(f"Save sync answered with something unreadable: {e}") from e


def _gui(configs=CONFIGS):
    """(api key, base url) from Syncthing's own config, or (None, None) before its first start."""
    for path in configs:
        try:
            root = ET.parse(path).getroot()
        except (OSError, ET.ParseError):
            continue
        gui = root.find("gui")
        if gui is None:
            continue
        address = (gui.findtext("address") or "127.0.0.1:8384").strip()
        scheme = "https" if gui.get("tls") == "true" else "http"
        return gui.findtext("apikey"), f"{scheme}://{address}/rest"
    return None, None


def _get(base, key, path):
    ctx = None
    if base.startswith("https"):
        # Syncthing's own self-signed certificate, on a connection that never leaves the handheld.
        import ssl
        ctx = ssl._create_unverified_context()
    req = urllib.request.Request(f"{base}/{path}", headers={"X-API-Key": key})
    with urllib.request.urlopen(req, timeout=5, context=ctx) as r:
        return json.loads(r.read().decode() or "null")


def sync_status(get=_get, gui=_gui):
    st = {"installed": Path(SYNC).exists(), "on": ENABLED_LINK.is_symlink(), "running": False,
          "deviceId": "", "devices": [], "pending": [], "folders": []}
    if not st["installed"] or not st["on"]:
        return st
    key, base = gui()
    if not key:
        return st
    try:
        me = get(base, key, "system/status")["myID"]
        config = get(base, key, "config")
        conns = (get(base, key, "system/connections") or {}).get("connections", {})
        pending = get(base, key, "cluster/pending/devices") or {}
    except (OSError, urllib.error.URLError, ValueError, KeyError, TypeError):
        return st  # stopped, or still starting
    st["running"] = True
    st["deviceId"] = me
    st["devices"] = [{"id": d["deviceID"], "name": d.get("name") or d["deviceID"][:7],
                      "connected": bool(conns.get(d["deviceID"], {}).get("connected"))}
                     for d in config.get("devices", []) if d["deviceID"] != me]
    st["pending"] = [{"id": i, "name": p.get("name") or i[:7], "address": p.get("address", "")}
                     for i, p in pending.items()]
    st["folders"] = [{"id": f["id"], "label": f.get("label", f["id"]), "path": f["path"],
                      "shared": len(f.get("devices", [])) > 1}
                     for f in config.get("folders", []) if f["id"] in FOLDER_IDS]
    return st


def _locked(args, timeout):
    if not _lock.acquire(blocking=False):
        raise RuntimeError("Save sync is busy, give it a moment")
    try:
        return _run(args, timeout)
    finally:
        _lock.release()


def set_sync(on):
    return _locked(["on" if on else "off"], timeout=60)


def accept_device(device_id):
    if not DEVICE_ID.fullmatch(device_id or ""):
        raise ValueError(f"Not a Syncthing device id: {device_id!r}")
    return _locked(["accept", device_id], timeout=30)
