import { ButtonItem, DialogButton, Field, Focusable, ModalRoot, PanelSection, PanelSectionRow, ProgressBar, showModal } from "@decky/ui";
import { useEffect, useRef, useState } from "react";
import { calibrationCancel, calibrationReset, calibrationSave, calibrationStart, calibrationStatus } from "../backend";
import type { CalibrationLive, CalibrationStatus } from "../types";
import { t } from "../i18n";
import { errorText } from "../lib/util";

function instruction(s: CalibrationStatus) {
  if (s.kind === "trigger") {
    return s.stage === "release"
      ? `Let go of the ${s.control?.toLowerCase()} and keep your hands off`
      : `Press the ${s.control?.toLowerCase()} all the way in and hold it`;
  }
  return s.stage === "release"
    ? `Let go of the ${s.control?.toLowerCase()} and keep your hands off`
    : `Push the ${s.control?.toLowerCase()} fully ${s.direction} and hold it there`;
}

function Bar({ label, value, signed }: { label: string; value: number; signed?: boolean }) {
  const pct = Math.round((signed ? (value + 1) / 2 : value) * 100);
  return (
    <div style={{ display: "flex", alignItems: "center", gap: "8px", marginBottom: "4px" }}>
      <div style={{ width: "120px", fontSize: "12px" }}>{label}</div>
      <div style={{ flex: 1 }}>
        <ProgressBar nProgress={pct} nTransitionSec={0} />
      </div>
      <div style={{ width: "48px", textAlign: "right", fontSize: "12px" }}>
        {signed ? `${Math.round(value * 100)}` : `${pct}%`}
      </div>
    </div>
  );
}

function LiveBars({ live }: { live?: CalibrationLive }) {
  if (!live) return null;
  return (
    <div style={{ margin: "8px 0" }}>
      <Bar label={t("Left stick X")} value={live.lx} signed />
      <Bar label={t("Left stick Y")} value={live.ly} signed />
      <Bar label={t("Right stick X")} value={live.rx} signed />
      <Bar label={t("Right stick Y")} value={live.ry} signed />
      <Bar label={t("Left trigger")} value={live.lt} />
      <Bar label={t("Right trigger")} value={live.rt} />
    </div>
  );
}

function CalibrationModal({ closeModal }: { closeModal?: () => void }) {
  const [status, setStatus] = useState<CalibrationStatus | null>(null);
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);
  const phaseRef = useRef("idle");
  phaseRef.current = status?.phase || "idle";

  // also the backend's watchdog heartbeat (calibration.py WATCHDOG_S)
  useEffect(() => {
    let cancelled = false;
    let inFlight = false;
    const tick = async () => {
      if (inFlight) return;
      inFlight = true;
      try {
        const next = await calibrationStatus();
        if (!cancelled) setStatus(next);
      } catch (error) {
        if (!cancelled) setMessage(errorText(error));
      } finally {
        inFlight = false;
      }
    };
    tick();
    const timer = window.setInterval(tick, 100);
    return () => {
      cancelled = true;
      window.clearInterval(timer);
      if (phaseRef.current !== "idle") calibrationCancel().catch(() => {});
    };
  }, []);

  const run = async (action: () => Promise<CalibrationStatus>) => {
    if (busy) return;
    setBusy(true);
    setMessage("");
    try {
      setStatus(await action());
    } catch (error) {
      setMessage(errorText(error));
    } finally {
      setBusy(false);
    }
  };

  const phase = status?.phase || "idle";
  const error = message || status?.error || "";
  return (
    <ModalRoot closeModal={phase === "capture" ? undefined : closeModal} bDisableBackgroundDismiss={phase !== "idle"}>
      <div style={{ fontWeight: 600, fontSize: "18px", marginBottom: "8px" }}>{t("Controller Calibration")}</div>
      {!status ? (
        <div>{t("Loading…")}</div>
      ) : !status.available ? (
        <div>{t("This device's gamepad driver does not support calibration.")}</div>
      ) : phase === "capture" ? (
        <>
          <div style={{ fontSize: "12px", opacity: 0.7 }}>
            Step {status.step + 1} of {status.steps} · the controller is paused for Steam until this finishes
          </div>
          <div style={{ fontSize: "20px", margin: "16px 0" }}>{instruction(status)}</div>
          <ProgressBar nProgress={Math.round(status.progress * 100)} nTransitionSec={0} />
          <LiveBars live={status.live} />
          <Focusable style={{ display: "flex", gap: "8px", marginTop: "12px" }}>
            <DialogButton onClick={() => run(calibrationCancel)}>{t("Cancel (touch)")}</DialogButton>
          </Focusable>
        </>
      ) : phase === "review" ? (
        <>
          <div>
            {t("Calibration applied. Check the sticks and triggers below: a full push should read 100 at the edge and 0 at rest. Save keeps it across reboots.")}
          </div>
          <LiveBars live={status.live} />
          <Focusable style={{ display: "flex", gap: "8px", marginTop: "12px" }}>
            <DialogButton disabled={busy} onClick={() => run(calibrationSave)}>{t("Save")}</DialogButton>
            <DialogButton disabled={busy} onClick={() => run(calibrationCancel)}>{t("Discard")}</DialogButton>
          </Focusable>
        </>
      ) : (
        <>
          <div>
            {status.saved ? "A saved calibration is in use." : "Using the driver defaults."} Start walks each stick
            and trigger to its edge and back. The controller is paused for Steam while it runs; Cancel works by touch.
          </div>
          <LiveBars live={status.live} />
          <Focusable style={{ display: "flex", gap: "8px", marginTop: "12px" }}>
            <DialogButton disabled={busy} onClick={() => run(calibrationStart)}>{t("Start")}</DialogButton>
            <DialogButton disabled={busy} onClick={() => run(calibrationReset)}>{t("Reset to Defaults")}</DialogButton>
            <DialogButton disabled={busy} onClick={() => closeModal?.()}>{t("Close")}</DialogButton>
          </Focusable>
        </>
      )}
      {error ? <div style={{ marginTop: "8px", color: "#ff8080" }}>{error}</div> : null}
    </ModalRoot>
  );
}

export function Calibration() {
  // Hidden where the gamepad driver has no calibration parameters (an AYANEO or KONKR pad).
  const [available, setAvailable] = useState<boolean | null>(null);
  useEffect(() => {
    calibrationStatus()
      .then((status) => setAvailable(status.available))
      .catch(() => setAvailable(false));
  }, []);
  if (!available) return null;
  return (
    <PanelSection title={t("CALIBRATION")}>
      <Field label={t("Sticks and triggers")} description={t("Stick centre and range, trigger travel")} />
      <PanelSectionRow>
        <ButtonItem layout="below" onClick={() => showModal(<CalibrationModal />)}>
          {t("Calibrate Controller")}
        </ButtonItem>
      </PanelSectionRow>
    </PanelSection>
  );
}
