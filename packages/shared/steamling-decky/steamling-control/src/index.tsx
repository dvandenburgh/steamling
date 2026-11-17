import { definePlugin } from "@decky/api";
import { Content } from "./Content";
import { getConfig } from "./backend";
import { installedSteamGames, isGame, nonSteamShortcuts } from "./lib/games";
import { registerDownloadWrapper, wrapAllGames, wrapShortcuts } from "./lib/launchOptions";
import { patchLibraryContextMenu } from "./lib/contextMenu";
import { pluginIcon } from "./icons";
import { registerTouchLifetime } from "./lib/touch";
import { applyToSteamWindow, getMenuWidth } from "./lib/menuWidth";
import { patchDeckyChrome } from "./lib/deckyChrome";

export default definePlugin(() => {
  const unpatchContextMenu = patchLibraryContextMenu();
  const unregisterTouch = registerTouchLifetime();
  const unregisterDownloads = registerDownloadWrapper((appid) => isGame(appid));
  const unpatchDeckyChrome = patchDeckyChrome();
  // Wider from the first time the menu opens, not only once this plugin's page has been shown.
  applyToSteamWindow(getMenuWidth());
  getConfig()
    .then((config) => wrapAllGames(installedSteamGames(config)))
    .then(() => wrapShortcuts(nonSteamShortcuts().map((shortcut) => shortcut.appid)))
    .catch(() => {});
  return {
    name: "Governor",
    content: <Content />,
    icon: pluginIcon,
    alwaysRender: true,
    onDismount() {
      unpatchContextMenu();
      unregisterTouch();
      unregisterDownloads();
      unpatchDeckyChrome();
      applyToSteamWindow(null);
    },
  };
});
