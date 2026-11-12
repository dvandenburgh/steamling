import { call } from "@decky/api";
import type { CacheInfo, CalibrationStatus, Config, ConfigExportResult, ConfigImportResult, ConfigPreview, DeviceInfo, LedConfig, LedSideKey, OverlayStatus, PaddleStatus, PanelStatus, RumbleStatus, SdcardInfo, ShareStatus, SnapshotStatus, SyncStatus, SshStatus, SystemStats, TuningStatus, Tweaks, UpdateInfo, UpdateStatus, UsbTransferStatus } from "./types";

export const getConfig = () => call<[], Config>("get_config");
// The setters answer with only what they changed: a full get_config re-reads the whole Steam
// library, in an emulated x86 Python.
export type Modes = Pick<Config, "fanMode" | "lavdMode">;
export const setFanMode = (mode: string) => call<[string], Modes>("set_fan_mode", mode);
export const setLavdMode = (mode: string) => call<[string], Modes>("set_lavd_mode", mode);
export const gameLifetime = (appid: string, running: boolean) => call<[string, boolean], void>("game_lifetime", appid, running);
export const saveTweaks = (data: Tweaks) => call<[Tweaks], Pick<Config, "tweaks">>("save_tweaks", data);
export const exportConfig = (appid: string, name: string, basename: string, allowOverwrite: boolean) =>
  call<[string, string, string, boolean], ConfigExportResult>("export_config", appid, name, basename, allowOverwrite);
export const configDir = () => call<[], string>("config_dir");
export const readConfig = (path: string) => call<[string], ConfigPreview>("read_config", path);
export const applyConfig = (path: string, sourceAppid: string, targetAppid: string, targetName: string) =>
  call<[string, string, string, string], ConfigImportResult>("apply_config", path, sourceAppid, targetAppid, targetName);
export const setLed = (side: LedSideKey, r: number, g: number, b: number, brightness: number) =>
  call<[LedSideKey, number, number, number, number], LedConfig>("set_led", side, r, g, b, brightness);
export const setLedLinked = (linked: boolean) => call<[boolean], LedConfig>("set_led_linked", linked);
export const setLedEnabled = (enabled: boolean) => call<[boolean], LedConfig>("set_led_enabled", enabled);
export const setLedSides = (sides: boolean) => call<[boolean], LedConfig>("set_led_sides", sides);
export const detectSdcard = () => call<[], SdcardInfo>("detect_sdcard");
export const formatSdcard = (label: string) => call<[string], SdcardInfo>("format_sdcard", label);
export const shareStatus = () => call<[], ShareStatus>("share_status");
export const setShare = (on: boolean) => call<[boolean], ShareStatus>("set_share", on);
export const installSamba = () => call<[], ShareStatus>("install_samba");
export const syncStatus = () => call<[], SyncStatus>("sync_status");
export const setSync = (on: boolean) => call<[boolean], SyncStatus>("set_sync", on);
export const acceptDevice = (id: string) => call<[string], SyncStatus>("accept_device", id);
export const deviceInfo = () => call<[], DeviceInfo>("device_info");
export const sshStatus = () => call<[], SshStatus>("ssh_status");
export const setSsh = (on: boolean) => call<[boolean], SshStatus>("set_ssh", on);
export const usbTransferStatus = () => call<[], UsbTransferStatus>("usb_transfer_status");
export const setUsbTransfer = (on: boolean) => call<[boolean], UsbTransferStatus>("set_usb_transfer", on);
export const restartGameMode = () => call<[], boolean>("restart_game_mode");
export const checkUpdates = () => call<[], UpdateInfo[]>("check_updates");
export const startUpdate = () => call<[], UpdateStatus>("start_update");
export const updateStatus = () => call<[], UpdateStatus>("update_status");
export const snapshotStatus = () => call<[], SnapshotStatus>("snapshot_status");
export const startRollback = (id: string) => call<[string], SnapshotStatus>("start_rollback", id);
export const rebootSystem = () => call<[], boolean>("reboot_system");
export const calibrationStatus = () => call<[], CalibrationStatus>("calibration_status");
export const calibrationStart = () => call<[], CalibrationStatus>("calibration_start");
export const calibrationCancel = () => call<[], CalibrationStatus>("calibration_cancel");
export const calibrationSave = () => call<[], CalibrationStatus>("calibration_save");
export const calibrationReset = () => call<[], CalibrationStatus>("calibration_reset");
export const panelStatus = () => call<[], PanelStatus>("panel_status");
export const panelCalibrate = () => call<[], PanelStatus>("panel_calibrate");
export const panelReset = () => call<[], PanelStatus>("panel_reset");
export const cacheInfo = (appid: string) => call<[string], CacheInfo>("cache_info", appid);
export const clearCache = (appid: string) => call<[string], CacheInfo>("clear_cache", appid);
export const rumbleStatus = () => call<[], RumbleStatus>("rumble_status");
export const setRumble = (enabled: boolean, strength: number) =>
  call<[boolean, number], RumbleStatus>("set_rumble", enabled, strength);
export const tuningStatus = () => call<[], TuningStatus>("tuning_status");
export const setTuning = (stick: string, deadzone: number, outer: number) =>
  call<[string, number, number], TuningStatus>("set_tuning", stick, deadzone, outer);
export const paddleStatus = () => call<[], PaddleStatus>("paddle_status");
export const setPaddles = (left: string, right: string) => call<[string, string], PaddleStatus>("set_paddles", left, right);
export const overlayStatus = () => call<[], OverlayStatus>("overlay_status");
export const setOverlay = (level: string) => call<[string], OverlayStatus>("set_overlay", level);
export const systemStats = () => call<[], SystemStats>("system_stats");
