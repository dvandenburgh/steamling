import { PanelSection } from "@decky/ui";
import { useEffect, useState } from "react";
import { setTuning, tuningStatus } from "../backend";
import { t } from "../i18n";
import type { StickTuning, TuningStatus } from "../types";
import { SelectEdit } from "./widgets";
import { errorText } from "../lib/util";

const deadzones = [50, 75, 100, 150, 200, 300];
const outers = [100, 95, 90, 85, 80];

function Stick({ label, stick, value, save }: {
  label: string;
  stick: "left" | "right";
  value: StickTuning;
  save: (stick: "left" | "right", next: StickTuning) => void;
}) {
  const dzOptions = deadzones.map((pct) => ({
    data: pct,
    label: pct === 100 ? t("Calibrated (100%)") : pct < 100 ? t("Smaller ({pct}%)", { pct }) : t("Bigger ({pct}%)", { pct }),
  }));
  const outerOptions = outers.map((pct) => ({
    data: pct,
    label: pct === 100 ? t("At the edge") : t("At {pct}% of the way", { pct }),
  }));
  return (
    <>
      <SelectEdit label={t("{stick}: dead zone", { stick: label })} value={value.deadzone} options={dzOptions as any}
        onChange={(pct) => save(stick, { ...value, deadzone: Number(pct) })} />
      <SelectEdit label={t("{stick}: full tilt", { stick: label })} value={value.outer} options={outerOptions as any}
        onChange={(pct) => save(stick, { ...value, outer: Number(pct) })} />
    </>
  );
}

export function StickResponse() {
  const [status, setStatus] = useState<TuningStatus | null>(null);
  const [error, setError] = useState("");

  useEffect(() => {
    tuningStatus().then(setStatus).catch((err) => setError(errorText(err)));
  }, []);

  if (!status?.available) return null;

  const save = (stick: "left" | "right", next: StickTuning) => {
    setError("");
    setStatus({ ...status, [stick]: next });
    setTuning(stick, next.deadzone, next.outer)
      .then(setStatus)
      .catch((err) => setError(errorText(err)));
  };

  return (
    <PanelSection title={t("STICK RESPONSE")}>
      <Stick label={t("Left stick")} stick="left" value={status.left} save={save} />
      <Stick label={t("Right stick")} stick="right" value={status.right} save={save} />
      <div className="steamling-note">
        {error ||
          t("Dead zone: how far a stick moves before it registers, relative to calibration. Full tilt: how far you push to reach 100%. Applies everywhere, kept across reboots. Steam Input adds per-game curves on top.")}
      </div>
    </PanelSection>
  );
}
