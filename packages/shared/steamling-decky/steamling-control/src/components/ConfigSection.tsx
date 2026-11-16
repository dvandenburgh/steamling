import { openFilePicker, toaster } from "@decky/api";
import { ButtonItem, ConfirmModal, PanelSection, PanelSectionRow, TextField, showModal } from "@decky/ui";
import { useState } from "react";
import { applyConfig, configDir, exportConfig, readConfig } from "../backend";
import { availableCompatTools, resolveCompatTool, setCompatTool } from "../lib/compat";
import { SelectEdit } from "./widgets";
import type { ConfigPreview } from "../types";
import { t } from "../i18n";
import { errorText } from "../lib/util";

function ExportNameModal({ game, base, onDone, closeModal }: {
  game: { appid: string; name: string };
  base: string;
  onDone: (path: string) => void;
  closeModal?: () => void;
}) {
  const [value, setValue] = useState(base);
  const [busy, setBusy] = useState(false);
  const overwriting = value.trim() === base;
  const submit = async () => {
    if (busy || !value.trim()) return;
    setBusy(true);
    try {
      const result = await exportConfig(game.appid, game.name, value.trim(), true);
      onDone(result.path);
    } catch (error) {
      toaster.toast({ title: t("Export failed"), body: errorText(error) });
    }
    closeModal?.();
  };
  return (
    <ConfirmModal
      strTitle={t("Config Already Exists")}
      strDescription={`${base}.steamling.json exists. Change the name to save a new config (e.g. ${base}-2 or ${base}-fast), or keep it to overwrite.`}
      strOKButtonText={busy ? "Saving…" : overwriting ? "Overwrite" : "Save New"}
      bOKDisabled={busy || !value.trim()}
      onCancel={() => closeModal?.()}
      onOK={submit}
    >
      <TextField label={t("Name")} value={value} disabled={busy} onChange={(event) => setValue(event.target.value)} />
    </ConfirmModal>
  );
}

function ImportModal({ path, preview, game, onDone, closeModal }: {
  path: string;
  preview: ConfigPreview;
  game: { appid: string; name: string };
  onDone: () => void;
  closeModal?: () => void;
}) {
  const profiles = preview.games;
  const [source, setSource] = useState(profiles[0]?.appid || "");
  const [busy, setBusy] = useState(false);
  const from = [preview.device, preview.exported].filter(Boolean).join(", ");
  const profileOptions = profiles.map((profile) => ({ data: profile.appid, label: profile.name || profile.appid }));
  const submit = async () => {
    if (busy || !source) return;
    setBusy(true);
    try {
      const result = await applyConfig(path, source, game.appid, game.name);
      if (result.protonTool) {
        const tools = await availableCompatTools(game.appid);
        const resolved = resolveCompatTool(result.protonTool, tools);
        if (resolved.tool) {
          setCompatTool(game.appid, resolved.tool);
          if (resolved.fallback) {
            toaster.toast({ title: t("Proton fallback"), body: `${result.protonTool} not available, using ${resolved.tool}` });
          }
        } else {
          toaster.toast({ title: t("Proton pick skipped"), body: `${result.protonTool} not available here` });
        }
      }
      toaster.toast({ title: t("Config applied"), body: game.name || game.appid });
    } catch (error) {
      toaster.toast({ title: t("Import failed"), body: errorText(error) });
    }
    closeModal?.();
    onDone();
  };
  return (
    <ConfirmModal
      strTitle={t("Import Game Config")}
      strDescription={(from ? `Exported from ${from}. ` : "") + `Settings for ${game.name || game.appid} will be overwritten.`}
      strOKButtonText={busy ? "Applying…" : "Apply"}
      bOKDisabled={busy || !source}
      onCancel={() => closeModal?.()}
      onOK={submit}
    >
      {profiles.length > 1 ? (
        <SelectEdit label={t("Profile")} value={source} options={profileOptions} onChange={(id) => setSource(String(id))} />
      ) : (
        <div className="steamling-note">Profile: {profiles[0]?.name || profiles[0]?.appid}</div>
      )}
    </ConfirmModal>
  );
}

/** Per-game config export/import; rendered only when a game's per-game settings are enabled. */
export function ConfigSection({ game, reload }: {
  game: { appid: string; name: string };
  reload: () => void;
}) {
  const doExport = async () => {
    try {
      const result = await exportConfig(game.appid, game.name || "", "", false);
      if (result.exists) {
        showModal(
          <ExportNameModal
            game={{ appid: game.appid, name: game.name || "" }}
            base={result.base}
            onDone={(path) => toaster.toast({ title: t("Game config exported"), body: path })}
          />,
        );
        return;
      }
      toaster.toast({ title: t("Game config exported"), body: result.path });
    } catch (error) {
      toaster.toast({ title: t("Export failed"), body: errorText(error) });
    }
  };
  const doImport = async () => {
    let path = "";
    try {
      const dir = await configDir().catch(() => "/home/deck");
      // 0 = FileSelectionType.FILE (same const-enum note as AddGame).
      const picked = await openFilePicker(0, dir, true, true);
      path = picked?.path || "";
    } catch (error) {
      return; // picker closed without a selection
    }
    if (!path) return;
    try {
      const preview = await readConfig(path);
      showModal(<ImportModal path={path} preview={preview} game={game} onDone={reload} />);
    } catch (error) {
      toaster.toast({ title: t("Import failed"), body: errorText(error) });
    }
  };
  return (
    <PanelSection title={t("CONFIG")}>
      <PanelSectionRow>
        <ButtonItem layout="below" onClick={doExport}>{t("Export Game Config")}</ButtonItem>
      </PanelSectionRow>
      <PanelSectionRow>
        <ButtonItem layout="below" onClick={doImport}>{t("Import Game Config")}</ButtonItem>
      </PanelSectionRow>
      <div className="steamling-note">{t("Per-game tweaks and Proton pick; fan settings and defaults stay local")}</div>
    </PanelSection>
  );
}
