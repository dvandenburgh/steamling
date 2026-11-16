import { PanelSection, PanelSectionRow, SliderField, ToggleField } from "@decky/ui";
import { useEffect, useRef, useState } from "react";
import { rumbleStatus, setRumble } from "../backend";
import { t } from "../i18n";
import type { RumbleStatus } from "../types";
import { errorText } from "../lib/util";

const STRENGTHS = [25, 50, 75, 100];

export function Rumble() {
  const [rumble, setRumbleState] = useState<RumbleStatus | null>(null);
  const [error, setError] = useState("");
  const timer = useRef<number | undefined>(undefined);

  useEffect(() => {
    rumbleStatus().then(setRumbleState).catch((err) => setError(errorText(err)));
  }, []);

  if (!rumble || (!rumble.canSwitch && !rumble.canScale)) return null;

  // Shown at once, written once the slider settles: dragging it fires onChange per notch.
  const save = (enabled: boolean, strength: number) => {
    setError("");
    setRumbleState({ ...rumble, enabled, strength });
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => {
      setRumble(enabled, strength)
        .then(setRumbleState)
        .catch((err) => setError(errorText(err)));
    }, 300);
  };

  const index = Math.max(0, STRENGTHS.indexOf(rumble.strength));
  return (
    <PanelSection title={t("RUMBLE")}>
      {rumble.canSwitch ? (
        <PanelSectionRow>
          <ToggleField
            label={t("Enable rumble")}
            checked={rumble.enabled}
            onChange={(on: boolean) => save(on, rumble.strength)}
          />
        </PanelSectionRow>
      ) : null}
      {rumble.canScale ? (
        <PanelSectionRow>
          <SliderField
            label={t("Strength")}
            value={index}
            min={0}
            max={STRENGTHS.length - 1}
            step={1}
            notchCount={STRENGTHS.length}
            notchLabels={STRENGTHS.map((pct, i) => ({ notchIndex: i, label: `${pct}%` }))}
            notchTicksVisible={true}
            disabled={rumble.canSwitch && !rumble.enabled}
            onChange={(i: number) => save(rumble.enabled, STRENGTHS[i] ?? 100)}
          />
        </PanelSectionRow>
      ) : null}
      {error ? <div className="steamling-note">{error}</div> : null}
    </PanelSection>
  );
}
