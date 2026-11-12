interface GameTweak {
  enabled?: boolean;
  name?: string;
  fexProfile?: string;
  /** Audio buffer in ms (PULSE_LATENCY_MSEC exported by steamling-game-launch); "" = game default. */
  audioLatency?: string;
  /** Turnip series pin ("25.2"); steamling-game-launch picks arch + point release. "" = default. */
  mesaVersion?: string;
  /** Space-separated KEY=VALUE pairs applied at launch; launch options win over these. */
  envVars?: string;
  /** Per-game fan curve override, applied for the game session only; "" = use global. */
  fanMode?: string;
  /** Per-game scx_lavd mode override, applied for the game session only; "" = use global. */
  lavdMode?: string;
  /** steamling-game-launch exports PROTON_USE_XALIA=0 unless false; absent = disabled. */
  disableXalia?: boolean;
  /** true = the touchscreen is inhibited while this game runs (steamling_control/touch.py). */
  touchDisabled?: boolean;
  /** Virtual pad while this game runs (steamling_control/gamepad.py); "" = game mode's Steam Deck pad. */
  gamepadType?: string;
  [key: string]: any;
}

export interface Tweaks {
  global: Record<string, any>;
  games: Record<string, GameTweak>;
}

interface InstalledGame {
  appid: string;
  name: string;
}

interface FexProfile {
  label: string;
  config?: Record<string, string>;
  /** STEAM_COMPAT_FEX_CONFIG string steamling-game-launch exports for Valve's x86 FEX; "" = none. */
  steam?: string;
}

export interface GameRef {
  appid: string;
  name: string;
  nonSteam?: boolean;
}

export interface Config {
  fanMode: string;
  lavdMode: string;
  tweaks: Tweaks;
  fexProfiles: Record<string, FexProfile>;
  /** Turnip payload choices, one per series (data "25.2"); the label marks single-arch series. */
  mesaVersions?: DropdownChoice[];
  installedGames: InstalledGame[];
  /** Known-good per-game settings, by appid (steamling_control/suggestions.py). */
  suggestions?: Record<string, GameSuggestion>;
  led: LedConfig;
  /** What this handheld has; controls for anything missing are hidden. */
  hardware?: { fan: boolean; scheduler: boolean; touchscreen: boolean; padSwitch: boolean };
  game?: GameRef | null;
  selectedGame?: GameRef | null;
}

export interface GameSuggestion {
  name: string;
  settings: Record<string, any>;
  /** Steam compat tool name to pick, or "" to leave it. */
  proton: string;
  note: string;
  tested: string;
}

export interface DropdownChoice {
  data: string;
  label: string;
}

export interface UpdateInfo {
  name: string;
  current: string;
  latest: string;
}

export interface UpdateStatus {
  running: boolean;
  log: string;
  exitCode: number | null;
}

interface SnapshotInfo {
  id: string;
  created: string;
  ok: boolean;
  /** true when that transaction included a kernel (rollback restores /flash boot files too) */
  kernel: boolean;
  targets: string;
}

export interface SnapshotStatus {
  supported: boolean;
  freeBytes: number;
  totalBytes: number;
  lowSpace: boolean;
  rebootRequired: boolean;
  rolledBack: { fromSnapshot: string; ts: string } | null;
  /** oldest -> newest; "roll back last update" targets the last entry */
  snapshots: SnapshotInfo[];
}

export interface ConfigExportResult {
  /** true = target file already exists and nothing was written (rename/overwrite flow). */
  exists: boolean;
  base: string;
  path: string;
}

export interface ConfigPreview {
  device: string;
  exported: string;
  games: { appid: string; name: string; protonTool: string }[];
}

export interface ConfigImportResult {
  protonTool: string;
  fexProfile?: string;
  enabled?: boolean;
}

export interface SdcardInfo {
  present: boolean;
  bootDisk?: boolean;
  device?: string;
  sizeBytes?: number;
  fstype?: string;
  label?: string;
  mountpoint?: string;
}

export interface LedSide {
  r: number;
  g: number;
  b: number;
  brightness: number;
}

export type LedSideKey = "left" | "right" | "both";

export interface LedConfig {
  available: boolean;
  sidesAvailable: boolean;
  enabled: boolean;
  linked: boolean;
  sides: boolean;
  left: LedSide;
  right: LedSide;
}

export type ShareStatus = {
  installed: boolean;
  on: boolean;
  active: boolean;
};

export type SyncDevice = { id: string; name: string; connected: boolean };
export type SyncPending = { id: string; name: string; address: string };
export type SyncFolder = { id: string; label: string; path: string; shared: boolean };
export type SyncStatus = {
  installed: boolean;
  on: boolean;
  running: boolean;
  deviceId: string;
  devices: SyncDevice[];
  pending: SyncPending[];
  folders: SyncFolder[];
};

export type SshStatus = {
  available: boolean;
  on: boolean;
  addresses: string[];
};

export type UsbTransferStatus = {
  available: boolean;
  on: boolean;
};

export type DeviceInfo = {
  osVersion: string;
  kernel: string;
  /** "" when there is nothing useful to say (no kit installed). */
  bootloader: string;
};

export type PanelStatus = {
  available: boolean;
  saved: boolean;
  running: boolean;
  // set by a calibration run: the mode trimmed, the frame length moved, the rate before and after
  result?: { rate: number; from: number; to: number; before: number; after: number };
};

export interface CalibrationLive {
  lx: number;
  ly: number;
  rx: number;
  ry: number;
  lt: number;
  rt: number;
}

export interface CalibrationStatus {
  available: boolean;
  backend: string;
  saved: boolean;
  phase: "idle" | "capture" | "review";
  step: number;
  steps: number;
  progress: number;
  error: string;
  result: Record<string, number>;
  control?: string;
  kind?: "stick" | "trigger";
  direction?: string;
  stage?: "push" | "release";
  live?: CalibrationLive;
}

export type OverlayStatus = {
  available: boolean;
  /** off | fps | compact | detailed | full, or custom when Steam wrote something else */
  level: string;
};

export interface SystemStats {
  cpu: { load: number | null; clusters: { cpus: string; mhz: number; maxMhz: number }[] };
  gpu: { mhz: number; maxMhz: number } | null;
  temps: { cpu?: number; gpu?: number };
  battery: { percent: number | null; status: string; watts: number | null; tempC: number | null } | null;
  memory: { usedMb: number; totalMb: number } | null;
  fan: { rpm: number | null; percent: number | null } | null;
}

export type CacheInfo = {
  appid: string;
  bytes: number;
};

export type RumbleStatus = {
  /** a gamepad driver with a rumble on/off switch is loaded */
  canSwitch: boolean;
  /** a vibration motor whose strength can be set is present */
  canScale: boolean;
  enabled: boolean;
  /** percent: 25, 50, 75 or 100 */
  strength: number;
};

/** Percentages of the calibrated values: deadzone 50-300, outer (full tilt) 80-100. */
export type StickTuning = { deadzone: number; outer: number };

export type TuningStatus = {
  available: boolean;
  left: StickTuning;
  right: StickTuning;
};

export type PaddleStatus = {
  /** a pad with back paddles is connected */
  available: boolean;
  /** InputPlumber button name the paddle sends instead, "" = stays a back button */
  left: string;
  right: string;
};
