import { useQuickAccessVisible } from "@decky/api";
import { Field, PanelSection, Tabs } from "@decky/ui";
import { useCallback, useEffect, useRef, useState } from "react";
import type { ReactNode } from "react";
import { getConfig, saveTweaks } from "./backend";
import { MenuWidthStyle } from "./components/MenuWidth";
import { useDebouncedSave } from "./hooks/useDebouncedSave";
import { QamVisible } from "./hooks/useQamVisible";
import { tabIcons } from "./icons";
import { currentGame } from "./lib/games";
import { onGameLifetime } from "./lib/touch";
import { styles } from "./styles";
import { Controller } from "./tabs/Controller";
import { Display } from "./tabs/Display";
import { Games } from "./tabs/Games";
import { Library } from "./tabs/Library";
import { Updater } from "./tabs/Updater";
import type { Config } from "./types";

// A loader whose API lacks the hook gets the old behaviour (always treated as open) instead of
// a crash; the choice is fixed per load, so hook order stays stable.
const useVisible: () => boolean = typeof useQuickAccessVisible === "function" ? useQuickAccessVisible : () => true;

export function Content() {
  const [tab, setTab] = useState("Games");
  const [config, setConfig] = useState<Config | null>(null);
  const [message, setMessage] = useState("Loading");
  const savedTweaksSnapshot = useRef("");
  const visible = useVisible();
  const configRef = useRef(config);
  configRef.current = config;
  const load = useCallback(async () => {
    try {
      const next = await getConfig();
      next.game = currentGame();
      next.selectedGame = next.game || null;
      savedTweaksSnapshot.current = JSON.stringify(next.tweaks);
      setConfig(next);
    } catch (error) {
      setMessage(String(error));
    }
  }, []);
  useEffect(() => {
    load();
  }, [load]);
  // Mounted once for the whole session, so re-read on every open: games installed since, and
  // edits saved from a library context-menu modal, which this copy would otherwise overwrite
  // on its next save. Skipped while an edit of our own is still waiting to be saved.
  const wasVisible = useRef(visible);
  useEffect(() => {
    const opened = visible && !wasVisible.current;
    wasVisible.current = visible;
    if (!opened) return;
    const current = configRef.current;
    if (current && JSON.stringify(current.tweaks) !== savedTweaksSnapshot.current) return;
    load();
  }, [visible, load]);
  // Track the running game so opening the QAM mid-game edits that game's profile: read on every
  // open, then on Steam's own start/stop notifications rather than by polling. The router may
  // update a moment after the notification, hence the short delay.
  useEffect(() => {
    if (!config || !visible) return;
    let cancelled = false;
    const refreshRuntime = () => {
      try {
        const runtimeGame = currentGame();
        if (cancelled) return;
        setConfig((current) => {
          if (!current) return current;
          if ((current.game?.appid || "") === (runtimeGame?.appid || "") && (current.game?.name || "") === (runtimeGame?.name || "")) return current;
          return { ...current, game: runtimeGame };
        });
      } catch (error) {
      }
    };
    let timer: number | undefined;
    const unsubscribe = onGameLifetime(() => {
      window.clearTimeout(timer);
      timer = window.setTimeout(refreshRuntime, 500);
    });
    refreshRuntime();
    return () => {
      cancelled = true;
      window.clearTimeout(timer);
      unsubscribe();
    };
  }, [!!config, visible]);
  useDebouncedSave({ config, field: "tweaks", snapshot: savedTweaksSnapshot, save: saveTweaks, setConfig, onError: load });

  if (!config) return <PanelSection title="Governor"><Field label={message} /></PanelSection>;

  const tabContent = (content: ReactNode) => (
    <div className="steamling-control-tab-content">{content}</div>
  );
  const tabs = [
    { id: "Games", title: tabIcons.Games, content: tabContent(<Games config={config} setConfig={setConfig} reload={load} />) },
    { id: "Display", title: tabIcons.Display, content: tabContent(<Display />) },
    { id: "Library", title: tabIcons.Library, content: tabContent(<Library />) },
    { id: "Controller", title: tabIcons.Controller, content: tabContent(<Controller config={config} setConfig={setConfig} reload={load} />) },
    { id: "Updater", title: tabIcons.Updater, content: tabContent(<Updater />) },
  ];
  return (
    <QamVisible.Provider value={visible}>
      <div className="steamling-control-tabs">
        <style>{styles}</style>
        <MenuWidthStyle />
        <Tabs activeTab={tab} onShowTab={setTab} tabs={tabs} />
      </div>
    </QamVisible.Provider>
  );
}
