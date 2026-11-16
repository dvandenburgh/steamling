import { PanelSection } from "@decky/ui";
import { useEffect, useRef, useState } from "react";
import { overlayStatus, setOverlay } from "../backend";
import { useQamVisible } from "../hooks/useQamVisible";
import { t } from "../i18n";
import type { OverlayStatus } from "../types";
import { SelectEdit } from "./widgets";
import { errorText } from "../lib/util";

export function PerformanceOverlay() {
  const [overlay, setOverlayState] = useState<OverlayStatus | null>(null);
  const [error, setError] = useState("");
  const busy = useRef(false);
  const visible = useQamVisible();

  // Re-read on every open: Steam's own Performance Overlay setting writes the same file.
  useEffect(() => {
    if (!visible) return;
    let cancelled = false;
    overlayStatus()
      .then((next) => {
        if (!cancelled && !busy.current) setOverlayState(next);
      })
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, [visible]);

  if (!overlay?.available) return null;

  const options = [
    { data: "off", label: t("Off") },
    { data: "fps", label: t("FPS only") },
    { data: "compact", label: t("Compact bar: FPS, CPU, GPU, RAM, battery") },
    { data: "detailed", label: t("Detailed: adds clocks, temperatures, power") },
    { data: "full", label: t("Everything") },
  ];
  if (overlay.level === "custom") options.push({ data: "custom", label: t("Set from Steam") });

  const change = async (level: string) => {
    if (busy.current || level === "custom") return;
    busy.current = true;
    setError("");
    try {
      setOverlayState(await setOverlay(level));
    } catch (err) {
      setError(errorText(err));
    } finally {
      busy.current = false;
    }
  };

  return (
    <PanelSection title={t("PERFORMANCE OVERLAY")}>
      <SelectEdit label={t("Show on screen")} value={overlay.level} options={options} onChange={change} />
      <div className="steamling-note">
        {error || t("Stays from game to game. Steam's own Performance Overlay setting changes it too, until the next game starts.")}
      </div>
    </PanelSection>
  );
}
