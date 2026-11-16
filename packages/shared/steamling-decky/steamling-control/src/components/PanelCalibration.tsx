import { ButtonItem, DialogButton, Field, Focusable, ModalRoot, PanelSection, PanelSectionRow, showModal } from "@decky/ui";
import { useEffect, useRef, useState } from "react";
import { panelCalibrate, panelReset, panelStatus } from "../backend";
import { useQamVisible } from "../hooks/useQamVisible";
import type { PanelStatus } from "../types";
import { t } from "../i18n";
import { errorText } from "../lib/util";

// Panels leave the factory a touch fast or slow, and emulators that pace to the display drift
// against their audio. steamling-panel-calibration measures the running refresh rate and trims the
// panel's frame length until it sits on the nominal rate; the result is kept across reboots.
function PanelModal({ initial, onChange, closeModal }: { initial: PanelStatus; onChange: (s: PanelStatus) => void; closeModal?: () => void }) {
  const [status, setStatus] = useState(initial);
  const [busy, setBusy] = useState(initial.running);
  const [error, setError] = useState("");
  const busyRef = useRef(busy);
  busyRef.current = busy;

  const run = async (action: () => Promise<PanelStatus>) => {
    if (busyRef.current) return;
    setBusy(true);
    setError("");
    try {
      const next = await action();
      setStatus(next);
      onChange(next);
    } catch (e) {
      setError(errorText(e));
    } finally {
      setBusy(false);
    }
  };

  const result = status.result;
  return (
    <ModalRoot closeModal={busy ? undefined : closeModal} bDisableBackgroundDismiss={busy}>
      <div style={{ fontSize: "20px", fontWeight: "bold", marginBottom: "8px" }}>{t("Display Refresh Calibration")}</div>
      <div>
        {busy
          ? "Measuring… this takes up to a minute. Leave the device on this screen until it finishes."
          : `${status.saved ? "A saved calibration is in use." : "Using the panel's factory timing."} Calibrate measures the refresh rate and trims it to exactly the nominal rate, which keeps emulator audio and video in step.`}
      </div>
      {result && !busy ? (
        <div style={{ marginTop: "8px" }}>
          {`${result.rate} Hz: measured ${result.before.toFixed(2)} Hz, now ${result.after.toFixed(2)} Hz.`}
        </div>
      ) : null}
      <Focusable style={{ display: "flex", gap: "8px", marginTop: "12px" }}>
        <DialogButton disabled={busy} onClick={() => run(panelCalibrate)}>{busy ? "Calibrating…" : "Calibrate"}</DialogButton>
        <DialogButton disabled={busy || !status.saved} onClick={() => run(panelReset)}>{t("Reset to Factory")}</DialogButton>
        <DialogButton disabled={busy} onClick={() => closeModal?.()}>{t("Close")}</DialogButton>
      </Focusable>
      {error ? <div style={{ marginTop: "8px", color: "#ff8080" }}>{error}</div> : null}
    </ModalRoot>
  );
}

export function PanelCalibration() {
  const [status, setStatus] = useState<PanelStatus | null>(null);
  const visible = useQamVisible();

  // One cheap sysfs read per menu open; panels without the attributes never show the section.
  useEffect(() => {
    if (!visible) return;
    let cancelled = false;
    panelStatus()
      .then((next) => { if (!cancelled) setStatus(next); })
      .catch(() => {});
    return () => { cancelled = true; };
  }, [visible]);

  if (!status?.available) return null;
  return (
    <PanelSection title={t("DISPLAY")}>
      <Field label={t("Refresh rate")} description={status.saved ? "Calibrated" : "Factory timing"} />
      <PanelSectionRow>
        <ButtonItem layout="below" onClick={() => showModal(<PanelModal initial={status} onChange={setStatus} />)}>
          {t("Calibrate Display")}
        </ButtonItem>
      </PanelSectionRow>
    </PanelSection>
  );
}
