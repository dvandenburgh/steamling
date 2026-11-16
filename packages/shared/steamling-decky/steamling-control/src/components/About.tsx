import { ButtonItem, ConfirmModal, Field, PanelSection, PanelSectionRow, showModal } from "@decky/ui";
import { useEffect, useState } from "react";
import { deviceInfo, restartGameMode } from "../backend";
import { useQamVisible } from "../hooks/useQamVisible";
import type { DeviceInfo } from "../types";
import { t } from "../i18n";
import { errorText } from "../lib/util";

export function About() {
  const [info, setInfo] = useState<DeviceInfo | null>(null);
  const [error, setError] = useState("");
  const visible = useQamVisible();

  // Once per open: the bootloader check reads both ABL slots, so it is not polled.
  useEffect(() => {
    if (!visible) return;
    let cancelled = false;
    deviceInfo()
      .then((next) => {
        if (!cancelled) setInfo(next);
      })
      .catch((err) => {
        if (!cancelled) setError(errorText(err));
      });
    return () => {
      cancelled = true;
    };
  }, [visible]);

  const confirmRestart = () =>
    showModal(
      <ConfirmModal
        strTitle={t("Restart Game Mode")}
        strDescription={t("Closes Steam and any running game, then brings game mode back up. Unsaved progress in a running game is lost. Useful when Steam or the screen gets stuck.")}
        strOKButtonText={t("Restart")}
        onOK={() => restartGameMode().catch((err) => setError(errorText(err)))}
      />
    );

  return (
    <PanelSection title={t("ABOUT")}>
      <Field label={t("Steamling OS")} description={info?.osVersion ?? "…"} />
      <Field label={t("Kernel")} description={info?.kernel ?? "…"} />
      {info?.bootloader ? <Field label={t("Bootloader")} description={info.bootloader} /> : null}
      <PanelSectionRow>
        <ButtonItem layout="below" onClick={confirmRestart}>{t("Restart Game Mode")}</ButtonItem>
      </PanelSectionRow>
      {error ? <Field label={t("Error")} description={error} /> : null}
    </PanelSection>
  );
}
