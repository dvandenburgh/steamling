import asyncio

from steamling_control import calibration, panel
from steamling_control.cache import cache_info, clear_cache
from steamling_control.config import build_config
from steamling_control.configio import apply_config, config_dir, export_config, read_config
from steamling_control.device import (
    device_info,
    restart_game_mode,
    set_ssh,
    set_usb_transfer,
    ssh_status,
    usb_transfer_status,
)
from steamling_control.gamepad import sync_gamepad
from steamling_control.led import restore_led, set_led, set_led_enabled, set_led_linked, set_led_sides
from steamling_control.modes import fan_mode, lavd_mode, set_fan_mode, set_lavd_mode
from steamling_control.overlay import overlay_status, reassert_in_background, set_overlay
from steamling_control.paddles import paddle_status, set_paddles
from steamling_control.rumble import restore_rumble, rumble_status, set_rumble
from steamling_control.savesync import accept_device, set_sync, sync_status
from steamling_control.sdcard import detect_sdcard, format_sdcard
from steamling_control.sharing import install_samba, set_share, share_status
from steamling_control.snapshots import reboot_system, snapshot_status, start_rollback
from steamling_control.stats import system_stats
from steamling_control.touch import sync_touch
from steamling_control.tuning import set_tuning, tuning_status
from steamling_control.tweaks import load_tweaks, save_tweaks
from steamling_control.updates import check_updates, start_update, update_status


class Plugin:
    # Appid of the running game, reported by the frontend's app-lifetime hook; drives the
    # touchscreen tweak. Starts None, so a (re)loaded backend turns touch back on.
    _running_appid = None

    # Offload blocking work to a thread so a slow call can't stall Decky's asyncio loop.
    async def get_config(self):
        return await asyncio.to_thread(build_config)

    async def _main(self):
        await asyncio.to_thread(restore_led)
        await asyncio.to_thread(restore_rumble)
        # The session starts the overlay off; put back the level picked here.
        reassert_in_background()
        await asyncio.to_thread(calibration.recover)
        await asyncio.to_thread(sync_touch, self._running_appid)

    async def _unload(self):
        await asyncio.to_thread(calibration.cancel)
        await asyncio.to_thread(sync_touch, None)
        await asyncio.to_thread(sync_gamepad, None)

    async def game_lifetime(self, appid, running):
        appid = str(appid or "")
        if running:
            self._running_appid = appid or None
        elif appid == self._running_appid:
            self._running_appid = None
        await asyncio.to_thread(sync_touch, self._running_appid)
        await asyncio.to_thread(sync_gamepad, self._running_appid)
        # Steam writes its own overlay level as a game starts or ends.
        reassert_in_background()

    async def detect_sdcard(self):
        return await asyncio.to_thread(detect_sdcard)

    async def format_sdcard(self, label):
        return await asyncio.to_thread(format_sdcard, label)

    async def sync_status(self):
        return await asyncio.to_thread(sync_status)

    async def set_sync(self, on):
        return await asyncio.to_thread(set_sync, on)

    async def accept_device(self, device_id):
        return await asyncio.to_thread(accept_device, device_id)

    async def share_status(self):
        return await asyncio.to_thread(share_status)

    async def set_share(self, on):
        return await asyncio.to_thread(set_share, on)

    async def install_samba(self):
        return await asyncio.to_thread(install_samba)

    async def device_info(self):
        return await asyncio.to_thread(device_info)

    async def ssh_status(self):
        return await asyncio.to_thread(ssh_status)

    async def set_ssh(self, on):
        return await asyncio.to_thread(set_ssh, bool(on))

    async def usb_transfer_status(self):
        return await asyncio.to_thread(usb_transfer_status)

    async def set_usb_transfer(self, on):
        return await asyncio.to_thread(set_usb_transfer, bool(on))

    async def restart_game_mode(self):
        return await asyncio.to_thread(restart_game_mode)

    # The setters answer with only the fields they change, which is all the frontend reads back:
    # get_config re-reads the whole Steam library, which is slow under FEX on an x86 loader.
    @staticmethod
    def _modes():
        return {"fanMode": fan_mode(), "lavdMode": lavd_mode()}

    async def set_fan_mode(self, mode):
        await asyncio.to_thread(set_fan_mode, mode)
        return self._modes()

    async def set_lavd_mode(self, mode):
        await asyncio.to_thread(set_lavd_mode, mode)
        return self._modes()

    async def save_tweaks(self, data):
        await asyncio.to_thread(save_tweaks, data)
        await asyncio.to_thread(sync_touch, self._running_appid)
        await asyncio.to_thread(sync_gamepad, self._running_appid)
        return {"tweaks": await asyncio.to_thread(load_tweaks)}

    async def export_config(self, appid, name, basename, allow_overwrite):
        return await asyncio.to_thread(export_config, appid, name, basename, allow_overwrite)

    async def config_dir(self):
        return await asyncio.to_thread(config_dir)

    async def read_config(self, path):
        return await asyncio.to_thread(read_config, path)

    async def apply_config(self, path, source_appid, target_appid, target_name):
        return await asyncio.to_thread(apply_config, path, source_appid, target_appid, target_name)

    # Not get_config(): that re-parses the whole Steam library, and a colour slider
    # commits repeatedly while it is being dialled in.
    async def set_led(self, side, r, g, b, brightness):
        return await asyncio.to_thread(set_led, side, r, g, b, brightness)

    async def set_led_linked(self, linked):
        return await asyncio.to_thread(set_led_linked, linked)

    async def set_led_enabled(self, enabled):
        return await asyncio.to_thread(set_led_enabled, enabled)

    async def set_led_sides(self, sides):
        return await asyncio.to_thread(set_led_sides, sides)

    async def check_updates(self):
        return await asyncio.to_thread(check_updates)

    async def start_update(self):
        return await asyncio.to_thread(start_update)

    async def update_status(self):
        return await asyncio.to_thread(update_status)

    async def snapshot_status(self):
        return await asyncio.to_thread(snapshot_status)

    async def start_rollback(self, snapshot_id):
        return await asyncio.to_thread(start_rollback, snapshot_id)

    async def reboot_system(self):
        return await asyncio.to_thread(reboot_system)

    async def calibration_status(self):
        return await asyncio.to_thread(calibration.status)

    async def calibration_start(self):
        return await asyncio.to_thread(calibration.start)

    async def calibration_cancel(self):
        return await asyncio.to_thread(calibration.cancel)

    async def calibration_save(self):
        return await asyncio.to_thread(calibration.save)

    async def calibration_reset(self):
        return await asyncio.to_thread(calibration.reset)

    async def panel_status(self):
        return await asyncio.to_thread(panel.status)

    async def panel_calibrate(self):
        return await asyncio.to_thread(panel.run)

    async def panel_reset(self):
        return await asyncio.to_thread(panel.reset)

    async def cache_info(self, appid):
        return await asyncio.to_thread(cache_info, str(appid))

    async def clear_cache(self, appid):
        return await asyncio.to_thread(clear_cache, str(appid), self._running_appid)

    async def rumble_status(self):
        return await asyncio.to_thread(rumble_status)

    async def set_rumble(self, enabled, strength):
        return await asyncio.to_thread(set_rumble, bool(enabled), int(strength))

    async def tuning_status(self):
        return await asyncio.to_thread(tuning_status)

    async def set_tuning(self, stick, deadzone, outer):
        return await asyncio.to_thread(set_tuning, str(stick), int(deadzone), int(outer))

    async def paddle_status(self):
        return await asyncio.to_thread(paddle_status)

    async def set_paddles(self, left, right):
        return await asyncio.to_thread(set_paddles, str(left), str(right))

    async def overlay_status(self):
        return await asyncio.to_thread(overlay_status)

    async def set_overlay(self, level):
        return await asyncio.to_thread(set_overlay, str(level))

    async def system_stats(self):
        return await asyncio.to_thread(system_stats)
