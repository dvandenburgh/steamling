import { ButtonItem, Field, PanelSection, PanelSectionRow, ToggleField } from "@decky/ui";
import { useEffect, useRef, useState } from "react";
import { acceptDevice, setSync, syncStatus } from "../backend";
import { useQamVisible } from "../hooks/useQamVisible";
import type { SyncStatus } from "../types";
import { t } from "../i18n";

// Syncthing pairing from a handheld: typing a 63-character device id with a gamepad is no fun,
// so the id is shown here for the PC side, and the PC's request shows up here to accept.
export function SaveSync() {
  const [sync, setSyncState] = useState<SyncStatus | null>(null);
  const [busy, setBusy] = useState(false);
  const [status, setStatus] = useState("");
  const busyRef = useRef(false);
  busyRef.current = busy;
  const visible = useQamVisible();

  // Polled only while the menu is open; each poll asks Syncthing, so not too often.
  useEffect(() => {
    if (!visible) return;
    let cancelled = false;
    const refresh = async () => {
      if (busyRef.current) return;
      try {
        const next = await syncStatus();
        if (!cancelled && !busyRef.current) setSyncState(next);
      } catch (error) {
        if (!cancelled) setStatus(String(error));
      }
    };
    refresh();
    const timer = window.setInterval(refresh, 10000);
    return () => {
      cancelled = true;
      window.clearInterval(timer);
    };
  }, [visible]);

  const run = async (action: () => Promise<SyncStatus>) => {
    if (busyRef.current) return;
    setBusy(true);
    setStatus("");
    try {
      setSyncState(await action());
    } catch (error) {
      setStatus(String(error));
    } finally {
      setBusy(false);
    }
  };

  if (sync && !sync.installed) return null;

  const connected = sync?.devices.filter((d) => d.connected).length ?? 0;
  const summary = () => {
    if (status) return status;
    if (!sync) return "Checking…";
    if (!sync.on) return "Off - saves stay on this handheld";
    if (!sync.running) return "Starting…";
    if (!sync.devices.length) return "On - add this handheld in Syncthing on your PC (device ID below)";
    return `On - ${connected} of ${sync.devices.length} paired device(s) connected`;
  };

  return (
    <PanelSection title={t("SAVE SYNC")}>
      <Field label={t("Syncthing")} description={summary()} />
      <PanelSectionRow>
        <ToggleField
          label={t("Sync emulator saves")}
          description={t("Keeps ~/Emulation/Saves and States in step with your PC")}
          checked={!!sync?.on}
          disabled={busy || !sync}
          onChange={(on: boolean) => run(() => setSync(on))}
        />
      </PanelSectionRow>
      {sync?.on && sync.deviceId ? (
        <Field label={t("This handheld's device ID")} description={sync.deviceId} />
      ) : null}
      {sync?.pending.map((p) => (
        <PanelSectionRow key={p.id}>
          <ButtonItem
            layout="below"
            disabled={busy}
            description={`${p.id.slice(0, 7)}… ${p.address}`}
            onClick={() => run(() => acceptDevice(p.id))}
          >
            {t("Accept {name}", { name: p.name })}
          </ButtonItem>
        </PanelSectionRow>
      ))}
    </PanelSection>
  );
}
