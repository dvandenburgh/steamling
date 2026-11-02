import os
import shutil

from .steam import STEAM_APPS_DIR, STEAM_ROOT, _steamapps_dirs

# Steam keeps each game's compiled shaders under <library>/steamapps/shadercache/<appid>: the
# Vulkan pipeline cache, DXVK/VKD3D state and Mesa's own cache, since Steam points Mesa there per
# game. Throwing it away is safe; the game rebuilds it, with some stutter while it does.
LIBRARY_FILES = (STEAM_APPS_DIR / "libraryfolders.vdf", STEAM_ROOT / "config/libraryfolders.vdf")


def _cache_dirs(appid, steamapps_dirs=None):
    appid = str(appid or "")
    if not appid.isdigit():
        raise ValueError(f"bad appid: {appid!r}")
    dirs = steamapps_dirs if steamapps_dirs is not None else _steamapps_dirs(LIBRARY_FILES)
    return [d / "shadercache" / appid for d in dirs if (d / "shadercache" / appid).is_dir()]


def _size(path):
    total = 0
    for root, _dirs, files in os.walk(path):
        for name in files:
            try:
                total += os.lstat(os.path.join(root, name)).st_size
            except OSError:
                pass
    return total


def cache_info(appid, steamapps_dirs=None):
    dirs = _cache_dirs(appid, steamapps_dirs)
    return {"appid": str(appid), "bytes": sum(_size(d) for d in dirs)}


def clear_cache(appid, running_appid, steamapps_dirs=None):
    if running_appid and str(running_appid) == str(appid):
        raise RuntimeError("Close the game first: it is using its shader cache")
    for d in _cache_dirs(appid, steamapps_dirs):
        # The cache dir only, never a link out of it.
        if d.is_symlink():
            d.unlink()
        else:
            shutil.rmtree(d, ignore_errors=True)
    return cache_info(appid, steamapps_dirs)
