import { Field, PanelSection, PanelSectionRow, ToggleField } from "@decky/ui";
import { useEffect, useRef, useState } from "react";
import { setUsbTransfer, usbTransferStatus } from "../backend";
import { useQamVisible } from "../hooks/useQamVisible";
import type { UsbTransferStatus } from "../types";
import { t } from "../i18n";
import { errorText } from "../lib/util";

export function UsbTransfer() {
  const [usb, setUsb] = useState<UsbTransferStatus | null>(null);
  const [busy, setBusy] = useState(false);
  const [status, setStatus] = useState("");
  const [readError, setReadError] = useState("");
  const busyRef = useRef(false);
  busyRef.current = busy;
  const visible = useQamVisible();

  useEffect(() => {
    if (!visible) return;
    let cancelled = false;
    usbTransferStatus()
      .then((next) => {
        if (cancelled || busyRef.current) return;
        setUsb(next);
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
      setUsb(await setUsbTransfer(on));
    } catch (error) {
      setStatus(errorText(error));
    } finally {
      setBusy(false);
    }
  };

  if (usb && !usb.available) return null;

  const summary = () => {
    if (status) return status;
    if (!usb) return readError || "Checking…";
    if (usb.on) return "On - plug into a computer with a USB-C cable and open \"Steamling\" like a phone. Controllers and hubs on the port stop working until you turn this off.";
    return "Off";
  };

  return (
    <PanelSection title={t("USB FILE TRANSFER")}>
      <Field label={t("Transfer over USB")} description={summary()} />
      <PanelSectionRow>
        <ToggleField
          label={t("Show up on a computer")}
          description={t("Copy files over a cable, no network needed. Stays on until you restart.")}
          checked={!!usb?.on}
          disabled={busy || !usb}
          onChange={(on: boolean) => run(on)}
        />
      </PanelSectionRow>
    </PanelSection>
  );
}
