import { PanelSection, ToggleField } from "@decky/ui";
import { useMemo } from "react";
import type { Dispatch, SetStateAction } from "react";
import { setFanMode, setLavdMode } from "../backend";
import type { Modes } from "../backend";
import { ConfigSection } from "../components/ConfigSection";
import { ShaderCache } from "../components/ShaderCache";
import { Suggestion } from "../components/Suggestion";
import { EnvVarsButton, PerfFields, hw, TouchField, TweakFields, XaliaToggle, audioLatencyOptions, fanOptions, lavdOptions } from "../components/GameFields";
import { SelectEdit } from "../components/widgets";
import { availableGames, editTargetOptions } from "../lib/games";
import { clone } from "../lib/util";
import type { Config } from "../types";
import { t } from "../i18n";

export function Games({ config, setConfig, reload }: {
  config: Config;
  setConfig: Dispatch<SetStateAction<Config | null>>;
  reload: () => void;
}) {
  const runtimeGame = config.game;
  // One app-store lookup per game: worth doing once per library change, not on every render.
  const games = useMemo(() => availableGames(config), [config.installedGames, config.tweaks.games]);
  const targetOptions = useMemo(() => editTargetOptions(games), [games]);
  const game = config.selectedGame || runtimeGame || null;
  const tweaks = config.tweaks;
  const gameSettings = game?.appid ? tweaks.games[game.appid] || {} : {};
  const editingDefault = !game?.appid;
  const perGameEnabled = !!(game?.appid && gameSettings.enabled === true);
  const values = editingDefault || !perGameEnabled ? tweaks.global : { ...tweaks.global, ...gameSettings };
  const patchSettings = (patch: Record<string, any>) => {
    setConfig((current) => {
      if (!current) return current;
      const next = { ...current, tweaks: clone(current.tweaks) };
      if (editingDefault) {
        Object.assign(next.tweaks.global, patch);
      } else if (perGameEnabled) {
        const existing = next.tweaks.games[game!.appid] || {};
        next.tweaks.games[game!.appid] = { ...existing, enabled: true, name: game!.name || "", ...patch };
      }
      return next;
    });
  };
  const setPerGameEnabled = (enabled: boolean) => {
    if (!game?.appid) return;
    setConfig((current) => {
      if (!current) return current;
      const next = { ...current, tweaks: clone(current.tweaks) };
      next.tweaks.games[game.appid] = {
        ...(next.tweaks.games[game.appid] || {}),
        enabled,
        name: game.name || "",
      };
      return next;
    });
  };
  // A suggestion turns per-game settings on and fills them in, in one save.
  const applySuggestion = (settings: Record<string, any>) => {
    if (!game?.appid) return;
    setConfig((current) => {
      if (!current) return current;
      const next = { ...current, tweaks: clone(current.tweaks) };
      next.tweaks.games[game.appid] = {
        ...(next.tweaks.games[game.appid] || {}),
        ...settings,
        enabled: true,
        name: game.name || "",
      };
      return next;
    });
  };
  // "" is the explicit Default target, not "nothing selected"; store a sentinel
  // so it doesn't fall back to the running game in the selectedGame derivation.
  const setSelectedGame = (appid: any) => {
    const id = String(appid);
    if (!id) {
      setConfig((current) => (current ? { ...current, selectedGame: { appid: "", name: "Default" } } : current));
      return;
    }
    const saved = games.find((candidate) => candidate.appid === id);
    setConfig((current) => (current ? { ...current, selectedGame: saved || null } : current));
  };

  // Default target: FEX/audio/env edit tweaks.global; fan + scheduler are the LIVE system
  // modes, applied immediately through the backend.
  const applyMode = async (setter: (mode: string) => Promise<Modes>, mode: string) => {
    try {
      const next = await setter(mode);
      setConfig((current) => (current ? { ...current, fanMode: next.fanMode, lavdMode: next.lavdMode } : current));
    } catch (error) {
      reload();
    }
  };
  const presets = config.fexProfiles || {};
  const storedProfile = values.fexProfile as string | undefined;
  const fexValue = storedProfile && presets[storedProfile] ? storedProfile : "default";
  const fexOptions = Object.entries(presets).map(([id, profile]) => ({ data: id, label: profile.label }));
  const storedLatency = String(values.audioLatency ?? "");
  const audioValue = audioLatencyOptions.some((option) => option.data === storedLatency) ? storedLatency : "";

  const showFields = editingDefault || perGameEnabled;
  const has = hw(config);
  const showPerf = showFields && (has.fan || has.scheduler);
  return (
    <>
      <PanelSection title={t("PERFORMANCE & GAME TWEAKS")}>
        <SelectEdit label={t("Game")} value={game?.appid || ""} options={targetOptions} onChange={setSelectedGame} />
        {!editingDefault ? <ToggleField label={t("Use Per-Game Settings")} checked={perGameEnabled} onChange={setPerGameEnabled} /> : null}
      </PanelSection>
      {!editingDefault ? <Suggestion config={config} appid={game!.appid} apply={applySuggestion} /> : null}
      {showPerf ? (
        <PanelSection title={t("PERFORMANCE")}>
          {editingDefault ? (
            <>
              {has.scheduler ? <SelectEdit label={t("CPU Scheduler")} value={config.lavdMode} options={lavdOptions} onChange={(mode) => applyMode(setLavdMode, mode)} /> : null}
              {has.fan ? <SelectEdit label={t("Fan Curve")} value={config.fanMode} options={fanOptions} onChange={(mode) => applyMode(setFanMode, mode)} /> : null}
            </>
          ) : (
            <PerfFields config={config} values={values} patch={patchSettings} />
          )}
        </PanelSection>
      ) : null}
      {showFields ? (
        <PanelSection title={t("GAME TWEAKS")}>
          <div className="steamling-note">{t("Changes apply on next game launch")}</div>
          {editingDefault ? (
            <>
              <SelectEdit
                label={t("FEX Preset")}
                value={fexValue}
                options={fexOptions}
                onChange={(id) => patchSettings({ fexProfile: id })}
              />
              <SelectEdit label={t("Audio Buffer")} value={audioValue} options={audioLatencyOptions} onChange={(id) => patchSettings({ audioLatency: id })} />
              <XaliaToggle values={values} patch={patchSettings} />
              {has.touchscreen ? <TouchField values={values} patch={patchSettings} /> : null}
              <EnvVarsButton value={String(values.envVars ?? "")} onSave={(next) => patchSettings({ envVars: next })} />
            </>
          ) : (
            <TweakFields config={config} appid={game!.appid} values={values} patch={patchSettings} />
          )}
        </PanelSection>
      ) : null}
      {!editingDefault && perGameEnabled ? (
        <ConfigSection game={{ appid: game!.appid, name: game!.name || "" }} reload={reload} />
      ) : null}
      {!editingDefault ? (
        <ShaderCache appid={game!.appid} name={game!.name || ""} running={runtimeGame?.appid === game!.appid} />
      ) : null}
    </>
  );
}
