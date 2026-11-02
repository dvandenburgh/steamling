import { PanelSection } from "@decky/ui";
import type { Dispatch, SetStateAction } from "react";
import { setFanMode, setLavdMode } from "../backend";
import type { Modes } from "../backend";
import { fanOptions, hw, lavdOptions } from "../components/GameFields";
import { PerformanceOverlay } from "../components/PerformanceOverlay";
import { SystemMonitor } from "../components/SystemMonitor";
import { SelectEdit } from "../components/widgets";
import type { Config } from "../types";
import { t } from "../i18n";

// How hard the handheld runs, and the numbers that show whether a change helped: the overlay
// first, since it's what people reach for mid-game.
export function Performance({ config, setConfig, reload }: {
  config: Config;
  setConfig: Dispatch<SetStateAction<Config | null>>;
  reload: () => void;
}) {
  const has = hw(config);
  // The live, handheld-wide modes, applied at once through the backend.
  const applyMode = async (setter: (mode: string) => Promise<Modes>, mode: string) => {
    try {
      const next = await setter(mode);
      setConfig((current) => (current ? { ...current, fanMode: next.fanMode, lavdMode: next.lavdMode } : current));
    } catch (error) {
      reload();
    }
  };
  return (
    <>
      <PerformanceOverlay />
      {has.scheduler || has.fan ? (
        <PanelSection title={t("CPU AND FAN")}>
          {has.scheduler ? <SelectEdit label={t("CPU Scheduler")} value={config.lavdMode} options={lavdOptions} onChange={(mode) => applyMode(setLavdMode, mode)} /> : null}
          {has.fan ? <SelectEdit label={t("Fan Curve")} value={config.fanMode} options={fanOptions} onChange={(mode) => applyMode(setFanMode, mode)} /> : null}
          <div className="steamling-note">{t("A game with its own settings on the This Game tab uses those while it runs")}</div>
        </PanelSection>
      ) : null}
      <SystemMonitor />
    </>
  );
}
