import { ButtonItem, ConfirmModal, PanelSectionRow, TextField, ToggleField, showModal } from "@decky/ui";
import { useEffect, useState } from "react";
import { availableCompatTools, registerForCompatTool, setCompatTool } from "../lib/compat";
import type { CompatTool } from "../lib/compat";
import { t } from "../i18n";
import { SelectEdit } from "./widgets";
import type { Config } from "../types";

// Audio buffer (PULSE_LATENCY_MSEC): absorbs FEX-mixer overruns (SFX-burst crackle) at the
// cost of audio latency — keep rhythm games on Game default.
export const audioLatencyOptions = [
  { data: "", label: t("Game default") },
  { data: "60", label: t("60 ms") },
  { data: "90", label: t("90 ms") },
  { data: "120", label: t("120 ms") },
];

export const fanOptions = [
  { data: "quiet", label: t("Quiet") },
  { data: "moderate", label: t("Moderate") },
  { data: "performance", label: t("Performance") },
];
export const lavdOptions = [
  { data: "autopilot", label: t("Autopilot") },
  { data: "performance", label: t("Performance") },
];
const globalChoice = { data: "", label: t("Use global") };

function EnvVarsModal({ initial, onSave, closeModal }: { initial: string; onSave: (value: string) => void; closeModal?: () => void }) {
  const [value, setValue] = useState(initial);
  return (
    <ConfirmModal
      strTitle={t("Environment Variables")}
      strDescription={'Space-separated KEY=VALUE pairs; quote values with spaces, e.g. DXVK_CONFIG="dxgi.customDeviceDesc = GTX 480". Steam launch options win over these.'}
      strOKButtonText={t("Save")}
      onCancel={() => closeModal?.()}
      onOK={() => {
        onSave(value.trim());
        closeModal?.();
      }}
    >
      <TextField label={t("Variables")} value={value} onChange={(event) => setValue(event.target.value)} />
    </ConfirmModal>
  );
}

export function EnvVarsButton({ value, onSave }: { value: string; onSave: (next: string) => void }) {
  return (
    <PanelSectionRow>
      <ButtonItem
        layout="below"
        description={value ? value : "None set"}
        onClick={() => showModal(<EnvVarsModal initial={value} onSave={onSave} />)}
      >
        {t("Environment Variables")}
      </ButtonItem>
    </PanelSectionRow>
  );
}

export function XaliaToggle({ values, patch }: {
  values: Record<string, any>;
  patch: (patch: Record<string, any>) => void;
}) {
  return (
    <PanelSectionRow>
      <ToggleField
        label={t("Disable Xalia")}
        description={t("Proton's controller-navigation helper; costs CPU in every game")}
        checked={values.disableXalia !== false}
        onChange={(checked) => patch({ disableXalia: checked })}
      />
    </PanelSectionRow>
  );
}

/** Applies live: the backend re-syncs the running game's touchscreen on every save. */
export function TouchField({ values, patch }: { values: Record<string, any>; patch: (patch: Record<string, any>) => void }) {
  return (
    <PanelSectionRow>
      <ToggleField
        label={t("Disable Touchscreen")}
        description={t("While the game is running, to stop stray touches")}
        checked={values.touchDisabled === true}
        onChange={(on) => patch({ touchDisabled: on })}
      />
    </PanelSectionRow>
  );
}

/** What the handheld has; an older backend that doesn't say counts as having everything. */
export function hw(config: Config) {
  return { fan: true, scheduler: true, touchscreen: true, padSwitch: true, ...(config.hardware || {}) };
}

/** Per-game fan/scheduler overrides ("" = follow the global mode); only the ones this handheld has. */
export function PerfFields({ config, values, patch }: {
  config: Config;
  values: Record<string, any>;
  patch: (patch: Record<string, any>) => void;
}) {
  const has = hw(config);
  const perGameFan = [globalChoice, ...fanOptions];
  const perGameLavd = [globalChoice, ...lavdOptions];
  const fanValue = perGameFan.some((option) => option.data === String(values.fanMode ?? "")) ? String(values.fanMode ?? "") : "";
  const lavdValue = perGameLavd.some((option) => option.data === String(values.lavdMode ?? "")) ? String(values.lavdMode ?? "") : "";
  return (
    <>
      {has.scheduler ? <SelectEdit label={t("CPU Scheduler")} value={lavdValue} options={perGameLavd} onChange={(id) => patch({ lavdMode: id })} /> : null}
      {has.fan ? <SelectEdit label={t("Fan Curve")} value={fanValue} options={perGameFan} onChange={(id) => patch({ fanMode: id })} /> : null}
    </>
  );
}

/** Applies live, like the touchscreen: the backend switches the pad when the game starts or stops. */
function GamepadTypeField({ values, patch }: { values: Record<string, any>; patch: (patch: Record<string, any>) => void }) {
  const options = [
    { data: "", label: t("Steam Deck (default)") },
    { data: "xb360", label: t("Xbox 360") },
    { data: "xbox-series", label: t("Xbox Series") },
    { data: "ds5", label: t("DualSense") },
  ];
  const stored = String(values.gamepadType ?? "");
  const value = options.some((option) => option.data === stored) ? stored : "";
  return (
    <>
      <SelectEdit label={t("Controller Type")} value={value} options={options} onChange={(id) => patch({ gamepadType: id })} />
      <div className="steamling-note">
        {t("What the game sees while it runs. Only matters with Steam Input turned off for the game.")}
      </div>
    </>
  );
}

/** The per-game tweak controls, shared by the This Game tab and the library context-menu modal. */
export function TweakFields({ config, appid, values, patch }: {
  config: Config;
  appid: string;
  values: Record<string, any>;
  patch: (patch: Record<string, any>) => void;
}) {
  // Proton pick is Steam's own per-game compat setting (see lib/compat.ts) — read live and
  // written straight back to Steam, so it mirrors the game-properties dropdown both ways.
  const [compatTools, setCompatTools] = useState<CompatTool[]>([]);
  const [currentTool, setCurrentTool] = useState("");
  useEffect(() => {
    setCompatTools([]);
    setCurrentTool("");
    if (!appid) return;
    let live = true;
    availableCompatTools(appid).then((tools) => {
      if (live) setCompatTools(tools);
    });
    const unregister = registerForCompatTool(appid, (tool) => {
      if (live) setCurrentTool(tool);
    });
    return () => {
      live = false;
      unregister();
    };
  }, [appid]);
  const compatOptions = [
    { data: "", label: t("Steam default") },
    ...compatTools.map((tool) => ({ data: tool.name, label: tool.label })),
  ];
  const compatValue = compatOptions.some((option) => option.data === currentTool) ? currentTool : "";

  const presets = config.fexProfiles || {};
  const storedProfile = values.fexProfile as string | undefined;
  const fexValue = storedProfile && presets[storedProfile] ? storedProfile : "default";
  const fexOptions = Object.entries(presets).map(([id, profile]) => ({ data: id, label: profile.label }));
  const storedLatency = String(values.audioLatency ?? "");
  const audioValue = audioLatencyOptions.some((option) => option.data === storedLatency) ? storedLatency : "";
  const mesaOptions = [{ data: "", label: t("System default") }, ...(config.mesaVersions || [])];
  const storedMesa = String(values.mesaVersion ?? "");
  const mesaValue = mesaOptions.some((option) => option.data === storedMesa) ? storedMesa : "";

  return (
    <>
      <SelectEdit
        label={t("Proton Version")}
        value={compatValue}
        options={compatOptions}
        onChange={(name) => {
          setCurrentTool(String(name));
          setCompatTool(appid, String(name));
        }}
      />
      <SelectEdit
        label={t("FEX Preset")}
        value={fexValue}
        options={fexOptions}
        onChange={(id) => patch({ fexProfile: id })}
      />
      <SelectEdit label={t("Audio Buffer")} value={audioValue} options={audioLatencyOptions} onChange={(id) => patch({ audioLatency: id })} />
      {(config.mesaVersions || []).length > 0 ? (
        <SelectEdit label={t("Mesa Version")} value={mesaValue} options={mesaOptions} onChange={(id) => patch({ mesaVersion: id })} />
      ) : null}
      <XaliaToggle values={values} patch={patch} />
      {hw(config).touchscreen ? <TouchField values={values} patch={patch} /> : null}
      {hw(config).padSwitch ? <GamepadTypeField values={values} patch={patch} /> : null}
      <EnvVarsButton value={String(values.envVars ?? "")} onSave={(next) => patch({ envVars: next })} />
    </>
  );
}
