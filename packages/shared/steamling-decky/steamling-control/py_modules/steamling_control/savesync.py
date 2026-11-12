import json
import os
import re
import threading
from pathlib import Path

from .system import run_cmd

# One implementation for the command line and the panel (steamling-emulation owns it). It runs as
# the deck user: Syncthing is that user's service, and the saves are theirs.
SYNC = "/usr/bin/steamling-sync"
HOME = Path("/home/deck")
DEVICE_ID = re.compile(r"[A-Z2-7]{7}(-[A-Z2-7]{7}){7}")

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


def sync_status():
    if not Path(SYNC).exists():
        return {"installed": False, "on": False, "running": False, "deviceId": "",
                "devices": [], "pending": [], "folders": []}
    return _run(["status"], timeout=20)


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
