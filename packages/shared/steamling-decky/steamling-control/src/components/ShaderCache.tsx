import { ButtonItem, ConfirmModal, PanelSection, PanelSectionRow, showModal } from "@decky/ui";
import { useEffect, useRef, useState } from "react";
import { cacheInfo, clearCache } from "../backend";
import { useQamVisible } from "../hooks/useQamVisible";
import { t } from "../i18n";
import { errorText, formatBytes } from "../lib/util";
import type { CacheInfo } from "../types";

export function ShaderCache({ appid, name, running }: { appid: string; name: string; running: boolean }) {
  const [info, setInfo] = useState<CacheInfo | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const busyRef = useRef(false);
  busyRef.current = busy;
  const visible = useQamVisible();

  useEffect(() => {
    if (!visible || !appid) return;
    let cancelled = false;
    setInfo(null);
    setError("");
    cacheInfo(appid)
      .then((next) => {
        if (!cancelled) setInfo(next);
      })
      .catch((err) => {
        if (!cancelled) setError(errorText(err));
      });
    return () => {
      cancelled = true;
    };
  }, [appid, visible]);

  const clear = async () => {
    if (busyRef.current) return;
    setBusy(true);
    setError("");
    try {
      setInfo(await clearCache(appid));
    } catch (err) {
      setError(errorText(err));
    } finally {
      setBusy(false);
    }
  };

  const size = info ? formatBytes(info.bytes) : "…";
  const description = () => {
    if (error) return error;
    if (running) return t("Close the game to clear it.");
    if (info && info.bytes === 0) return t("Nothing cached yet.");
    return t("Compiled shaders for this game. Clearing fixes some graphics glitches after a driver or game update; the game stutters a little while it rebuilds them.");
  };

  return (
    <PanelSection title={t("SHADER CACHE")}>
      <PanelSectionRow>
        <ButtonItem
          layout="below"
          description={description()}
          disabled={busy || running || !info || info.bytes === 0}
          onClick={() =>
            showModal(
              <ConfirmModal
                strTitle={t("Clear Shader Cache")}
                strDescription={t("Delete the {size} of compiled shaders kept for {name}? The game builds them again as it runs.", { size, name })}
                strOKButtonText={t("Clear")}
                onOK={clear}
              />
            )
          }
        >
          {busy ? t("Clearing…") : t("Clear Shader Cache ({size})", { size })}
        </ButtonItem>
      </PanelSectionRow>
    </PanelSection>
  );
}
