import { PanelSection } from "@decky/ui";
import { useEffect, useState } from "react";
import { paddleStatus, setPaddles } from "../backend";
import { t } from "../i18n";
import type { PaddleStatus } from "../types";
import { SelectEdit } from "./widgets";
import { errorText } from "../lib/util";

function options(side: "left" | "right") {
  return [
    { data: "", label: side === "left" ? t("Back button L4 (default)") : t("Back button R4 (default)") },
    { data: "South", label: t("A") },
    { data: "East", label: t("B") },
    { data: "West", label: t("X") },
    { data: "North", label: t("Y") },
    { data: "LeftBumper", label: t("L1 / LB") },
    { data: "RightBumper", label: t("R1 / RB") },
    { data: "LeftStick", label: t("L3 (left stick click)") },
    { data: "RightStick", label: t("R3 (right stick click)") },
    { data: "Select", label: t("Select / View") },
    { data: "Start", label: t("Start / Menu") },
  ];
}

export function BackPaddles() {
  const [status, setStatus] = useState<PaddleStatus | null>(null);
  const [error, setError] = useState("");

  useEffect(() => {
    paddleStatus().then(setStatus).catch(() => {});
  }, []);

  if (!status?.available) return null;

  const save = (left: string, right: string) => {
    setError("");
    setStatus({ ...status, left, right });
    setPaddles(left, right)
      .then(setStatus)
      .catch((err) => setError(errorText(err)));
  };

  return (
    <PanelSection title={t("BACK PADDLES")}>
      <SelectEdit label={t("Left paddle")} value={status.left} options={options("left")} onChange={(v) => save(String(v), status.right)} />
      <SelectEdit label={t("Right paddle")} value={status.right} options={options("right")} onChange={(v) => save(status.left, String(v))} />
      <div className="steamling-note">
        {error ||
          t("Remaps the paddles for everything, desktop mode and emulators included. Leave them as back buttons to map them per game in Steam Input instead.")}
      </div>
    </PanelSection>
  );
}
