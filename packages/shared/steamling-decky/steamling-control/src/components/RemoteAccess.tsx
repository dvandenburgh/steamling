import { ConfirmModal, Field, PanelSection, PanelSectionRow, ToggleField, showModal } from "@decky/ui";
import { useEffect, useRef, useState } from "react";
import { setSsh, sshStatus } from "../backend";
import { useQamVisible } from "../hooks/useQamVisible";
import type { SshStatus } from "../types";
import { t } from "../i18n";
import { errorText } from "../lib/util";

// Same warning the Steamling Tools menu shows: every image ships the same default password.
function SshConfirmModal({ onConfirm, closeModal }: { onConfirm: () => Promise<void>; closeModal?: () => void }) {
  const [running, setRunning] = useState(false);
  const runningRef = useRef(false);
  runningRef.current = running;
  const start = async () => {
    if (runningRef.current) return;
    setRunning(true);
    await onConfirm();
    closeModal?.();
  };
  return (
    <ConfirmModal
      strTitle={t("Allow SSH Logins")}
      strDescription={
        running
          ? "Starting…"
          : "Anyone on the same network can then log in with an account password, and Steamling ships a well-known default one. If you have not changed it yet, do that first: open Konsole in desktop mode and run passwd. It stays on, across reboots, until you turn it off here."
      }
      strOKButtonText={running ? "Starting…" : "Turn On SSH"}
      bDestructiveWarning={true}
      bOKDisabled={running}
      bCancelDisabled={running}
      bDisableBackgroundDismiss={true}
      onCancel={() => {
        if (!runningRef.current) closeModal?.();
      }}
      onOK={start}
    />
  );
}

export function RemoteAccess() {
  const [ssh, setSshState] = useState<SshStatus | null>(null);
  const [busy, setBusy] = useState(false);
  const [status, setStatus] = useState("");
  const [readError, setReadError] = useState("");
  const busyRef = useRef(false);
  busyRef.current = busy;
  const visible = useQamVisible();

  // Read once per open: nothing else flips it while the menu is up, and each read is a transient unit.
  useEffect(() => {
    if (!visible) return;
    let cancelled = false;
    sshStatus()
      .then((next) => {
        if (cancelled || busyRef.current) return;
        setSshState(next);
        setReadError("");
      })
      .catch((error) => {
        if (!cancelled) setReadError(errorText(error));
      });
    return () => {
      cancelled = true;
    };
  }, [visible]);

  const run = async (on: boolean) => {
    if (busyRef.current) return;
    setBusy(true);
    setStatus("");
    try {
      setSshState(await setSsh(on));
    } catch (error) {
      setStatus(errorText(error));
    } finally {
      setBusy(false);
    }
  };

  if (ssh && !ssh.available) return null;

  const summary = () => {
    if (status) return status;
    if (!ssh) return readError || "Checking…";
    if (!ssh.on) return "Off - the device does not accept SSH logins";
    if (ssh.addresses.length === 0) return "On - connect to Wi-Fi to reach it";
    return `On - ${ssh.addresses.map((a) => `ssh deck@${a}`).join(" or ")}`;
  };

  return (
    <PanelSection title={t("REMOTE ACCESS")}>
      <Field label={t("SSH")} description={summary()} />
      <PanelSectionRow>
        <ToggleField
          label={t("Allow SSH logins")}
          description={t("Log in from another computer's terminal")}
          checked={!!ssh?.on}
          disabled={busy || !ssh}
          onChange={(on: boolean) => {
            if (busyRef.current) return;
            if (on) showModal(<SshConfirmModal onConfirm={() => run(true)} />);
            else run(false);
          }}
        />
      </PanelSectionRow>
    </PanelSection>
  );
}
