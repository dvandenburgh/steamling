import { ButtonItem, Navigation, PanelSection, PanelSectionRow, QuickAccessTab, staticClasses } from "@decky/ui";
import { useEffect, useState } from "react";
import type { ReactNode } from "react";
import { governorMark, settingsIcon, storeIcon } from "../icons";
import { t } from "../i18n";

// Decky's own Quick Access tab, made Steamling's: the Governor mark in place of the plug on the
// tab, and Decky's store and settings as full-width rows under the plugin list instead of two
// small buttons beside the title. Decky has no API for either, so this edits the two elements
// it registered with its tab hook (window.__TABS_HOOK_INSTANCE, Decky 3.x): the icon's first child
// and the panel's content. Both sit inside Decky's DeckyStateContextProvider, which re-renders
// its children on every Decky state change, so a notifyUpdate makes the edit show. Anything not
// shaped as expected is left alone, so a Decky that changes its layout keeps its own.

type DeckyState = {
  _activePlugin?: unknown;
  eventBus?: EventTarget;
  notifyUpdate?: () => void;
};

const HOME_CLASS = "steamling-decky-home";

function onDecky(path: string) {
  Navigation.Navigate(path);
  Navigation.CloseSideMenus();
}

function Row({ icon, label, onClick }: { icon: ReactNode; label: string; onClick: () => void }) {
  return (
    <PanelSectionRow>
      <ButtonItem layout="below" onClick={onClick}>
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
          {icon}
          <div>{label}</div>
        </div>
      </ButtonItem>
    </PanelSectionRow>
  );
}

// Shown only on Decky's plugin list, not while a plugin's page is open.
function DeckyLinks({ state }: { state: DeckyState }) {
  const [listShown, setListShown] = useState(!state._activePlugin);
  useEffect(() => {
    const update = () => setListShown(!state._activePlugin);
    state.eventBus?.addEventListener("update", update);
    return () => state.eventBus?.removeEventListener("update", update);
  }, [state]);
  if (!listShown) return null;
  return (
    <PanelSection>
      <Row icon={storeIcon} label={t("Decky Store")} onClick={() => onDecky("/decky/store")} />
      <Row icon={settingsIcon} label={t("Decky Settings")} onClick={() => onDecky("/decky/settings")} />
    </PanelSection>
  );
}

// The title row's two small buttons go: on the plugin list Decky's TitleView is a direct child of
// the content (a plugin's page nests it one level down, so its back button stays).
function homeCss() {
  return `.${HOME_CLASS} > .${staticClasses.Title} > :not(:first-child) { display: none !important; }`;
}

export function patchDeckyChrome(): () => void {
  try {
    const hook = (window as any).__TABS_HOOK_INSTANCE;
    const tab = hook?.tabs?.find((candidate: any) => candidate?.id === QuickAccessTab.Decky);
    const icon = tab?.icon;
    const content = tab?.content;
    const state: DeckyState | undefined = content?.props?.deckyState;
    const iconKids = icon?.props?.children;
    if (!state || !Array.isArray(iconKids) || iconKids.length < 1 || !content?.props?.children) return () => {};
    if (Object.isFrozen(icon.props) || Object.isFrozen(iconKids) || Object.isFrozen(content.props)) return () => {};

    const plug = iconKids[0];
    const panel = content.props.children;
    iconKids[0] = governorMark("1em");
    content.props.children = (
      <div className={HOME_CLASS}>
        <style>{homeCss()}</style>
        {panel}
        <DeckyLinks state={state} />
      </div>
    );
    state.notifyUpdate?.();
    return () => {
      iconKids[0] = plug;
      content.props.children = panel;
      state.notifyUpdate?.();
    };
  } catch (error) {
    return () => {};
  }
}
