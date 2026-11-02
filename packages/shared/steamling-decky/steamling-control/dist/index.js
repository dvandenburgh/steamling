const manifest = {"name":"Governor"};
const API_VERSION = 2;
const internalAPIConnection = window.__DECKY_SECRET_INTERNALS_DO_NOT_USE_OR_YOU_WILL_BE_FIRED_deckyLoaderAPIInit;
if (!internalAPIConnection) {
    throw new Error('[@decky/api]: Failed to connect to the loader as as the loader API was not initialized. This is likely a bug in Decky Loader.');
}
let api;
try {
    api = internalAPIConnection.connect(API_VERSION, manifest.name);
}
catch {
    api = internalAPIConnection.connect(1, manifest.name);
    console.warn(`[@decky/api] Requested API version ${API_VERSION} but the running loader only supports version 1. Some features may not work.`);
}
if (api._version != API_VERSION) {
    console.warn(`[@decky/api] Requested API version ${API_VERSION} but the running loader only supports version ${api._version}. Some features may not work.`);
}
const call = api.call;
const toaster = api.toaster;
const openFilePicker = api.openFilePicker;
const useQuickAccessVisible = api.useQuickAccessVisible;
const definePlugin = (fn) => {
    return (...args) => {
        return fn(...args);
    };
};

const getConfig = () => call("get_config");
const setFanMode = (mode) => call("set_fan_mode", mode);
const setLavdMode = (mode) => call("set_lavd_mode", mode);
const gameLifetime = (appid, running) => call("game_lifetime", appid, running);
const saveTweaks = (data) => call("save_tweaks", data);
const exportConfig = (appid, name, basename, allowOverwrite) => call("export_config", appid, name, basename, allowOverwrite);
const configDir = () => call("config_dir");
const readConfig = (path) => call("read_config", path);
const applyConfig = (path, sourceAppid, targetAppid, targetName) => call("apply_config", path, sourceAppid, targetAppid, targetName);
const setLed = (side, r, g, b, brightness) => call("set_led", side, r, g, b, brightness);
const setLedLinked = (linked) => call("set_led_linked", linked);
const setLedEnabled = (enabled) => call("set_led_enabled", enabled);
const setLedSides = (sides) => call("set_led_sides", sides);
const detectSdcard = () => call("detect_sdcard");
const formatSdcard = (label) => call("format_sdcard", label);
const shareStatus = () => call("share_status");
const setShare = (on) => call("set_share", on);
const installSamba = () => call("install_samba");
const deviceInfo = () => call("device_info");
const sshStatus = () => call("ssh_status");
const setSsh = (on) => call("set_ssh", on);
const usbTransferStatus = () => call("usb_transfer_status");
const setUsbTransfer = (on) => call("set_usb_transfer", on);
const restartGameMode = () => call("restart_game_mode");
const checkUpdates = () => call("check_updates");
const startUpdate = () => call("start_update");
const updateStatus = () => call("update_status");
const snapshotStatus = () => call("snapshot_status");
const startRollback = (id) => call("start_rollback", id);
const rebootSystem = () => call("reboot_system");
const calibrationStatus = () => call("calibration_status");
const calibrationStart = () => call("calibration_start");
const calibrationCancel = () => call("calibration_cancel");
const calibrationSave = () => call("calibration_save");
const calibrationReset = () => call("calibration_reset");
const panelStatus = () => call("panel_status");
const panelCalibrate = () => call("panel_calibrate");
const panelReset = () => call("panel_reset");
const cacheInfo = (appid) => call("cache_info", appid);
const clearCache = (appid) => call("clear_cache", appid);
const rumbleStatus = () => call("rumble_status");
const setRumble = (enabled, strength) => call("set_rumble", enabled, strength);
const tuningStatus = () => call("tuning_status");
const setTuning = (stick, deadzone, outer) => call("set_tuning", stick, deadzone, outer);
const paddleStatus = () => call("paddle_status");
const setPaddles = (left, right) => call("set_paddles", left, right);
const overlayStatus = () => call("overlay_status");
const setOverlay = (level) => call("set_overlay", level);
const systemStats = () => call("system_stats");

// One entry per language, keyed by its two-letter code ("de", "es", ...). English is the source
// text in the code, so it needs no catalog.
const catalogs = {};

function language() {
    try {
        const steam = window.LocalizationManager?.m_rgLocalesToUse?.[0];
        const raw = String(steam || navigator.language || "en").toLowerCase();
        return raw.split(/[-_]/)[0];
    }
    catch (error) {
        return "en";
    }
}
let cached;
function catalog() {
    if (cached === undefined)
        cached = catalogs[language()] || null;
    return cached;
}
function t(text, vars) {
    let out = catalog()?.[text] ?? text;
    if (vars) {
        for (const [key, value] of Object.entries(vars))
            out = out.split(`{${key}}`).join(String(value));
    }
    return out;
}

// Steam draws the quick access menu 348px wide: a 48px tab strip plus a 300px page. The menu is
// its own window, sized and placed from a placeholder in Steam's main window that is 854px wide
// and shifted right by 506px, so 348px of it is on screen. Making the placeholder wider (it is
// anchored to the right edge) brings more of the menu on screen without touching the slide-in
// transform. The friends list's expanded view resizes itself and is left alone.
const WIDTHS = { standard: 0, wide: 100, wider: 200 };
const KEY = "steamling-control.menu-width";
const DEFAULT = "wide";
const listeners$1 = new Set();
function getMenuWidth() {
    try {
        const saved = window.localStorage.getItem(KEY);
        if (saved && saved in WIDTHS)
            return saved;
    }
    catch (error) {
    }
    return DEFAULT;
}
function setMenuWidth(width) {
    try {
        window.localStorage.setItem(KEY, width);
    }
    catch (error) {
    }
    for (const listener of listeners$1)
        listener(width);
}
function onMenuWidth(listener) {
    listeners$1.add(listener);
    return () => listeners$1.delete(listener);
}
// Steam's hashed class names, looked up by the names its own code uses. The placeholder lives in
// Steam's main window; the panel inside it is a separate window (the menu's own document).
const viewClasses = (DFL.findClassModule((m) => m.ViewPlaceholder && m.Expanded) || DFL.quickAccessMenuClasses);
const panelClasses = (DFL.findClassModule((m) => m.TabGroupPanel && m.HeaderContainer && m.Footer) || DFL.quickAccessMenuClasses);
function cls(map, key) {
    return map?.[key] ? `.${map[key].split(" ")[0]}` : "";
}
/** For Steam's main window: the placeholder sets the size and position of the menu's window. */
function placeholderCss(width) {
    const extra = WIDTHS[width];
    const placeholder = cls(viewClasses, "ViewPlaceholder");
    if (!extra || !placeholder)
        return "";
    const expanded = cls(viewClasses, "Expanded");
    const open = expanded ? `${placeholder}:not(${expanded})` : placeholder;
    return `${open} { width: ${854 + extra}px !important; }`;
}
/** For the menu's own window: let the page, header and footer fill the extra room. */
function panelCss(width) {
    const extra = WIDTHS[width];
    if (!extra)
        return "";
    const expanded = cls(viewClasses, "Expanded");
    const notExpanded = expanded ? `:not(${expanded} *)` : "";
    const rules = [];
    const panel = cls(panelClasses, "TabGroupPanel");
    const header = cls(panelClasses, "HeaderContainer");
    const footer = cls(panelClasses, "Footer");
    if (panel)
        rules.push(`${panel}:not(.tab_Friends) { max-width: ${300 + extra}px !important; }`);
    if (header)
        rules.push(`${header}${notExpanded} { max-width: ${348 + extra}px !important; }`);
    if (footer)
        rules.push(`${footer}${notExpanded} { width: ${348 + extra}px !important; }`);
    return rules.join("\n");
}
const STYLE_ID = "steamling-control-menu-width";
/** Puts the placeholder rule into Steam's main window, or takes it out again. */
function applyToSteamWindow(width) {
    let doc;
    try {
        doc = DFL.findSP()?.document;
    }
    catch (error) {
    }
    if (!doc)
        return;
    const css = width ? placeholderCss(width) : "";
    let style = doc.getElementById(STYLE_ID);
    if (!css) {
        style?.remove();
        return;
    }
    if (!style) {
        style = doc.createElement("style");
        style.id = STYLE_ID;
        doc.head.appendChild(style);
    }
    style.textContent = css;
}

function SelectEdit({ label, value, options, onChange }) {
    const rgOptions = options.map((option) => (typeof option === "string" ? { data: option, label: option } : option));
    return (SP_JSX.jsx(DFL.PanelSectionRow, { children: label === undefined ? (SP_JSX.jsx(DFL.Dropdown, { selectedOption: value, rgOptions: rgOptions, onChange: (option) => onChange(option.data) })) : (SP_JSX.jsx(DFL.DropdownItem, { label: label, selectedOption: value, rgOptions: rgOptions, onChange: (option) => onChange(option.data) })) }));
}

/** Mounted once by Content, which stays rendered for the whole session. The panel rules render
 * here, in the menu's window; the placeholder rule goes into Steam's main window. */
function MenuWidthStyle() {
    const [width, setWidth] = SP_REACT.useState(getMenuWidth);
    SP_REACT.useEffect(() => onMenuWidth(setWidth), []);
    SP_REACT.useEffect(() => applyToSteamWindow(width), [width]);
    const css = panelCss(width);
    return css ? SP_JSX.jsx("style", { children: css }) : null;
}
function MenuWidthSetting() {
    const [width, setWidth] = SP_REACT.useState(getMenuWidth);
    SP_REACT.useEffect(() => onMenuWidth(setWidth), []);
    const options = [
        { data: "standard", label: t("Standard (Steam's own)") },
        { data: "wide", label: t("Wide") },
        { data: "wider", label: t("Wider") },
    ];
    return (SP_JSX.jsxs(DFL.PanelSection, { title: t("QUICK ACCESS MENU"), children: [SP_JSX.jsx(SelectEdit, { label: t("Width"), value: width, options: options, onChange: (value) => setMenuWidth(value) }), SP_JSX.jsx("div", { className: "steamling-note", children: t("Widens this menu for every page in it, so text wraps less.") })] }));
}

function useDebouncedSave(options) {
    const { config, field, snapshot, save, setConfig, onError, delay = 900 } = options;
    const value = config ? config[field] : undefined;
    // Latest unsaved edit; written by the debounce timer or the unmount flush below.
    const pending = SP_REACT.useRef(null);
    const flush = SP_REACT.useCallback(async () => {
        const entry = pending.current;
        if (!entry)
            return;
        pending.current = null;
        try {
            const next = await save(entry.value);
            snapshot.current = JSON.stringify(next[field]);
            setConfig((stored) => {
                if (!stored)
                    return stored;
                if (JSON.stringify(stored[field]) !== entry.serialized)
                    return stored;
                return { ...stored, [field]: next[field] };
            });
        }
        catch (error) {
            onError?.(error);
        }
    }, [save, field, snapshot, setConfig, onError]);
    const flushRef = SP_REACT.useRef(flush);
    flushRef.current = flush;
    SP_REACT.useEffect(() => {
        if (!config || !snapshot.current)
            return;
        const current = JSON.stringify(value);
        if (current === snapshot.current) {
            pending.current = null;
            return;
        }
        pending.current = { value, serialized: current };
        const timer = window.setTimeout(() => flushRef.current(), delay);
        return () => window.clearTimeout(timer);
    }, [value]);
    // QAM panels unmount the moment the menu closes, and the cleanup above clears the only
    // pending timer: without this flush, any edit made <delay ms before closing is dropped.
    SP_REACT.useEffect(() => () => void flushRef.current(), []);
}

// The panel is alwaysRender: it stays mounted while the menu is closed and a game runs, so
// anything that polls asks this first. Content provides it from @decky/api's
// useQuickAccessVisible; outside the panel (library modals) the default is visible.
const QamVisible = SP_REACT.createContext(true);
const useQamVisible = () => SP_REACT.useContext(QamVisible);

function Icon({ path }) {
    return (SP_JSX.jsx("svg", { style: { display: "block" }, width: "20", height: "20", viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", strokeWidth: "2", strokeLinecap: "round", strokeLinejoin: "round", children: path }));
}
const tabIcons = {
    // Performance: a gauge with its needle swung toward high, for the fan curve, CPU scheduler,
    // overlay and system monitor that live under this tab.
    Games: (SP_JSX.jsx(Icon, { path: SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx("path", { d: "M3.34 19a10 10 0 1 1 17.32 0" }), SP_JSX.jsx("path", { d: "M6 14h1.5" }), SP_JSX.jsx("path", { d: "M12 6.5V8" }), SP_JSX.jsx("path", { d: "M16.5 14H18" }), SP_JSX.jsx("path", { d: "m12 14 4.5-4.5" }), SP_JSX.jsx("circle", { cx: "12", cy: "14", r: "1.5", fill: "currentColor" })] }) })),
    // Display: a screen with a pulse line on it, for the overlay, the live readings and the panel
    // settings under this tab.
    Display: (SP_JSX.jsx(Icon, { path: SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx("rect", { width: "20", height: "14", x: "2", y: "3", rx: "2" }), SP_JSX.jsx("path", { d: "M8 21h8" }), SP_JSX.jsx("path", { d: "M12 17v4" }), SP_JSX.jsx("path", { d: "M6 11h2.5l1.5-3 3 6 1.5-3H18" })] }) })),
    Library: (SP_JSX.jsx(Icon, { path: SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx("rect", { width: "18", height: "18", x: "3", y: "3", rx: "2" }), SP_JSX.jsx("path", { d: "M8 12h8" }), SP_JSX.jsx("path", { d: "M12 8v8" })] }) })),
    Updater: (SP_JSX.jsx(Icon, { path: SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx("path", { d: "M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" }), SP_JSX.jsx("polyline", { points: "7 10 12 15 17 10" }), SP_JSX.jsx("line", { x1: "12", x2: "12", y1: "15", y2: "3" })] }) })),
    // The gamepad: calibration, stick response, paddles and rumble all live under this tab.
    Controller: (SP_JSX.jsx(Icon, { path: SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx("line", { x1: "6", x2: "10", y1: "11", y2: "11" }), SP_JSX.jsx("line", { x1: "8", x2: "8", y1: "9", y2: "13" }), SP_JSX.jsx("line", { x1: "15", x2: "15.01", y1: "12", y2: "12" }), SP_JSX.jsx("line", { x1: "18", x2: "18.01", y1: "10", y2: "10" }), SP_JSX.jsx("path", { d: "M17.32 5H6.68a4 4 0 0 0-3.978 3.59c-.006.052-.01.101-.017.152C2.604 9.416 2 14.456 2 16a3 3 0 0 0 3 3c1 0 1.5-.5 2-1l1.414-1.414A2 2 0 0 1 9.828 16h4.344a2 2 0 0 1 1.414.586L17 18c.5.5 1 1 2 1a3 3 0 0 0 3-3c0-1.545-.604-6.584-.685-7.258-.007-.05-.011-.1-.017-.151A4 4 0 0 0 17.32 5z" })] }) })),
};
/** Governor's own icon: a flyball governor, the spinning regulator that holds a steam engine's speed. */
const pluginIcon = (SP_JSX.jsxs("svg", { width: "1em", height: "1em", viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", strokeWidth: "2", strokeLinecap: "round", strokeLinejoin: "round", children: [SP_JSX.jsx("line", { x1: "12", x2: "12", y1: "2", y2: "21" }), SP_JSX.jsx("path", { d: "M12 4 7.6 9.4M12 4l4.4 5.4" }), SP_JSX.jsx("circle", { cx: "6.5", cy: "11", r: "1.9", fill: "currentColor" }), SP_JSX.jsx("circle", { cx: "17.5", cy: "11", r: "1.9", fill: "currentColor" }), SP_JSX.jsx("path", { d: "M7.6 12.6 10.5 15.5M16.4 12.6 13.5 15.5" }), SP_JSX.jsx("rect", { x: "10", y: "15", width: "4", height: "2.5", rx: "0.5" }), SP_JSX.jsx("line", { x1: "7", x2: "17", y1: "21", y2: "21" })] }));

function gameDisplayName(game) {
    if (!game?.appid)
        return "";
    return game.name || `App ${game.appid}`;
}
// The backend lists every appmanifest in steamapps, tools included. app_type 4 = tool in
// Steam's appStore overview; this name pattern is the fallback when no overview exists.
const NON_GAME_NAME = /^(Proton[ 0-9]|Proton (Hotfix|EasyAntiCheat|BattlEye)|Steam Linux Runtime|Steamworks Common)/i;
function isGame(appid, name = "") {
    try {
        const overview = window.appStore?.GetAppOverviewByAppID?.(Number(appid));
        if (typeof overview?.app_type === "number")
            return overview.app_type !== 4;
    }
    catch (error) {
    }
    return !NON_GAME_NAME.test(name);
}
function installedSteamGames(config) {
    return (config.installedGames || [])
        .filter((game) => game?.appid && isGame(String(game.appid), game.name || ""))
        .map((game) => String(game.appid));
}
// Non-Steam shortcuts have no appmanifest, so only deckDesktopApps sees them. Their appids are
// unsigned and above 2^31, hence the >>> 0: some builds hand out the signed-int32 form.
function nonSteamShortcuts() {
    try {
        const ids = window.collectionStore?.deckDesktopApps?.apps;
        if (!ids?.values)
            return [];
        const shortcuts = [];
        for (const id of Array.from(ids.values())) {
            const appid = String(Number(id) >>> 0);
            if (!appid || appid === "0")
                continue;
            let name = "";
            try {
                name = window.appStore?.GetAppOverviewByAppID?.(Number(appid))?.display_name || "";
            }
            catch (error) {
            }
            shortcuts.push({ appid, name: name || `App ${appid}`, nonSteam: true });
        }
        return shortcuts;
    }
    catch (error) {
        return [];
    }
}
function availableGames(config) {
    const games = new Map();
    for (const game of config.installedGames || []) {
        if (game?.appid && isGame(String(game.appid), game.name || "")) {
            games.set(String(game.appid), { appid: String(game.appid), name: game.name || `App ${game.appid}` });
        }
    }
    for (const shortcut of nonSteamShortcuts()) {
        games.set(shortcut.appid, shortcut);
    }
    // Saved tweaks keep a game listed even when the lookups above miss it, so existing
    // per-game config can never become unreachable.
    for (const [appid, game] of Object.entries(config.tweaks?.games || {})) {
        if (game && typeof game === "object" && !games.has(String(appid))) {
            games.set(String(appid), { appid: String(appid), name: game.name || `App ${appid}`, nonSteam: Number(appid) >= 0x80000000 });
        }
    }
    return Array.from(games.values()).sort((a, b) => (a.nonSteam ? 1 : 0) - (b.nonSteam ? 1 : 0) || gameDisplayName(a).localeCompare(gameDisplayName(b)));
}
function editTargetOptions(games) {
    return [
        { data: "", label: "Default" },
        ...games.map((game) => ({
            data: game.appid,
            label: game.nonSteam ? `${gameDisplayName(game)} · non-Steam` : gameDisplayName(game),
        })),
    ];
}
function currentGame() {
    const running = DFL.Router?.MainRunningApp || window.Router?.MainRunningApp;
    const appid = running?.appid;
    if (!appid)
        return null;
    const id = String(appid);
    let name = running?.display_name || running?.displayName || "";
    try {
        const details = window.appDetailsStore?.GetAppDetails?.(Number(id));
        name = details?.strDisplayName || details?.strName || details?.name || name;
    }
    catch (error) {
    }
    return { appid: id, name: name || `App ${id}` };
}

// Anything else in the panel that cares when a game starts or stops listens here, instead of
// polling for it.
const listeners = new Set();
function onGameLifetime(listener) {
    listeners.add(listener);
    return () => listeners.delete(listener);
}
// Reports game start/stop to the backend, which owns the touchscreen tweak (touch.py). Covers
// every Steam launch, Proton or not, since the appid comes from Steam itself. Shortcut appids
// are unsigned above 2^31, hence the >>> 0 (see nonSteamShortcuts).
function registerTouchLifetime() {
    const report = (appid, running) => gameLifetime(appid, running).catch(() => { });
    // A plugin reload mid-game misses the start notification.
    const running = currentGame();
    if (running)
        report(running.appid, true);
    try {
        const handle = window.SteamClient?.GameSessions?.RegisterForAppLifetimeNotifications?.((update) => {
            report(String(Number(update?.unAppID) >>> 0), !!update?.bRunning);
            for (const listener of listeners) {
                try {
                    listener();
                }
                catch (error) {
                }
            }
        });
        return () => handle?.unregister?.();
    }
    catch (error) {
        return () => { };
    }
}

// The panel fills whatever width the quick access menu has. It used to be pinned to the Deck's
// 316px with position: fixed, which broke on screens where Steam lays the menu out at another
// scale (the RP6: oversized text, controls cut off). Armada fixed the same container this way.
const styles = `
      .steamling-control-tabs {
        width: 100%;
        height: 95vh;
        min-width: 0;
        min-height: 0;
      }
      .steamling-control-tabs > div {
        height: 100%;
        min-height: 0;
      }
      .steamling-control-tabs > div > div:first-child::before {
        background: #0D141C;
        box-shadow: none;
        backdrop-filter: none;
      }
      .steamling-control-tabs .${DFL.gamepadTabbedPageClasses.TabContents},
      .steamling-control-tabs .${DFL.gamepadTabbedPageClasses.TabContentsScroll},
      .steamling-control-tabs .steamling-control-tab-content {
        min-width: 0;
      }
      .steamling-control-tabs .${DFL.gamepadTabbedPageClasses.TabContentsScroll} {
        padding-left: 0;
        padding-right: 0;
      }
      .steamling-control-tabs [role="tablist"] {
        display: flex;
        flex-wrap: nowrap;
        justify-content: center;
      }
      .steamling-control-tabs [role="tab"] {
        flex: 0 1 auto;
        min-width: 0;
        box-sizing: border-box;
        padding-left: 6px;
        padding-right: 6px;
        display: flex;
        align-items: center;
        justify-content: center;
      }
      .steamling-control-tabs [role="tab"] svg {
        display: block;
        margin: 0;
      }
      .steamling-control-tabs .steamling-control-tab-content {
        padding-bottom: 24px;
      }
      .steamling-control-tabs .steamling-log {
        font-family: monospace;
        font-size: 10px;
        line-height: 14px;
        word-break: break-all;
        white-space: pre-wrap;
      }
      .steamling-control-tabs .steamling-note {
        box-sizing: border-box;
        width: 100%;
        padding: 8px 16px 8px;
        font-size: 12px;
        line-height: 16px;
        opacity: 0.62;
        text-align: left;
        justify-content: flex-start;
        align-self: stretch;
      }
    `;

function options(side) {
    return [
        { data: "", label: side === "left" ? t("Back button L4 (default)") : t("Back button R4 (default)") },
        { data: "South", label: t("A") },
        { data: "East", label: t("B") },
        { data: "West", label: t("X") },
        { data: "North", label: t("Y") },
        { data: "LeftBumper", label: t("L1 / LB") },
        { data: "RightBumper", label: t("R1 / RB") },
        { data: "LeftStick", label: t("L3 (left stick click)") },
        { data: "RightStick", label: t("R3 (right stick click)") },
        { data: "Select", label: t("Select / View") },
        { data: "Start", label: t("Start / Menu") },
    ];
}
function BackPaddles() {
    const [status, setStatus] = SP_REACT.useState(null);
    const [error, setError] = SP_REACT.useState("");
    SP_REACT.useEffect(() => {
        paddleStatus().then(setStatus).catch(() => { });
    }, []);
    if (!status?.available)
        return null;
    const save = (left, right) => {
        setError("");
        setStatus({ ...status, left, right });
        setPaddles(left, right)
            .then(setStatus)
            .catch((err) => setError(String(err)));
    };
    return (SP_JSX.jsxs(DFL.PanelSection, { title: t("BACK PADDLES"), children: [SP_JSX.jsx(SelectEdit, { label: t("Left paddle"), value: status.left, options: options("left"), onChange: (v) => save(String(v), status.right) }), SP_JSX.jsx(SelectEdit, { label: t("Right paddle"), value: status.right, options: options("right"), onChange: (v) => save(status.left, String(v)) }), SP_JSX.jsx("div", { className: "steamling-note", children: error ||
                    t("Remaps the paddles for everything, desktop mode and emulators included. Leave them as back buttons to map them per game in Steam Input instead.") })] }));
}

function instruction(s) {
    if (s.kind === "trigger") {
        return s.stage === "release"
            ? `Let go of the ${s.control?.toLowerCase()} and keep your hands off`
            : `Press the ${s.control?.toLowerCase()} all the way in and hold it`;
    }
    return s.stage === "release"
        ? `Let go of the ${s.control?.toLowerCase()} and keep your hands off`
        : `Push the ${s.control?.toLowerCase()} fully ${s.direction} and hold it there`;
}
function Bar({ label, value, signed }) {
    const pct = Math.round((signed ? (value + 1) / 2 : value) * 100);
    return (SP_JSX.jsxs("div", { style: { display: "flex", alignItems: "center", gap: "8px", marginBottom: "4px" }, children: [SP_JSX.jsx("div", { style: { width: "120px", fontSize: "12px" }, children: label }), SP_JSX.jsx("div", { style: { flex: 1 }, children: SP_JSX.jsx(DFL.ProgressBar, { nProgress: pct, nTransitionSec: 0 }) }), SP_JSX.jsx("div", { style: { width: "48px", textAlign: "right", fontSize: "12px" }, children: signed ? `${Math.round(value * 100)}` : `${pct}%` })] }));
}
function LiveBars({ live }) {
    if (!live)
        return null;
    return (SP_JSX.jsxs("div", { style: { margin: "8px 0" }, children: [SP_JSX.jsx(Bar, { label: t("Left stick X"), value: live.lx, signed: true }), SP_JSX.jsx(Bar, { label: t("Left stick Y"), value: live.ly, signed: true }), SP_JSX.jsx(Bar, { label: t("Right stick X"), value: live.rx, signed: true }), SP_JSX.jsx(Bar, { label: t("Right stick Y"), value: live.ry, signed: true }), SP_JSX.jsx(Bar, { label: t("Left trigger"), value: live.lt }), SP_JSX.jsx(Bar, { label: t("Right trigger"), value: live.rt })] }));
}
function CalibrationModal({ closeModal }) {
    const [status, setStatus] = SP_REACT.useState(null);
    const [message, setMessage] = SP_REACT.useState("");
    const [busy, setBusy] = SP_REACT.useState(false);
    const phaseRef = SP_REACT.useRef("idle");
    phaseRef.current = status?.phase || "idle";
    // also the backend's watchdog heartbeat (calibration.py WATCHDOG_S)
    SP_REACT.useEffect(() => {
        let cancelled = false;
        let inFlight = false;
        const tick = async () => {
            if (inFlight)
                return;
            inFlight = true;
            try {
                const next = await calibrationStatus();
                if (!cancelled)
                    setStatus(next);
            }
            catch (error) {
                if (!cancelled)
                    setMessage(String(error));
            }
            finally {
                inFlight = false;
            }
        };
        tick();
        const timer = window.setInterval(tick, 100);
        return () => {
            cancelled = true;
            window.clearInterval(timer);
            if (phaseRef.current !== "idle")
                calibrationCancel().catch(() => { });
        };
    }, []);
    const run = async (action) => {
        if (busy)
            return;
        setBusy(true);
        setMessage("");
        try {
            setStatus(await action());
        }
        catch (error) {
            setMessage(String(error));
        }
        finally {
            setBusy(false);
        }
    };
    const phase = status?.phase || "idle";
    const error = message || status?.error || "";
    return (SP_JSX.jsxs(DFL.ModalRoot, { closeModal: phase === "capture" ? undefined : closeModal, bDisableBackgroundDismiss: phase !== "idle", children: [SP_JSX.jsx("div", { style: { fontWeight: 600, fontSize: "18px", marginBottom: "8px" }, children: t("Controller Calibration") }), !status ? (SP_JSX.jsx("div", { children: t("Loading…") })) : !status.available ? (SP_JSX.jsx("div", { children: t("This device's gamepad driver does not support calibration.") })) : phase === "capture" ? (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsxs("div", { style: { fontSize: "12px", opacity: 0.7 }, children: ["Step ", status.step + 1, " of ", status.steps, " \u00B7 the controller is paused for Steam until this finishes"] }), SP_JSX.jsx("div", { style: { fontSize: "20px", margin: "16px 0" }, children: instruction(status) }), SP_JSX.jsx(DFL.ProgressBar, { nProgress: Math.round(status.progress * 100), nTransitionSec: 0 }), SP_JSX.jsx(LiveBars, { live: status.live }), SP_JSX.jsx(DFL.Focusable, { style: { display: "flex", gap: "8px", marginTop: "12px" }, children: SP_JSX.jsx(DFL.DialogButton, { onClick: () => run(calibrationCancel), children: t("Cancel (touch)") }) })] })) : phase === "review" ? (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx("div", { children: t("Calibration applied. Check the sticks and triggers below: a full push should read 100 at the edge and 0 at rest. Save keeps it across reboots.") }), SP_JSX.jsx(LiveBars, { live: status.live }), SP_JSX.jsxs(DFL.Focusable, { style: { display: "flex", gap: "8px", marginTop: "12px" }, children: [SP_JSX.jsx(DFL.DialogButton, { disabled: busy, onClick: () => run(calibrationSave), children: t("Save") }), SP_JSX.jsx(DFL.DialogButton, { disabled: busy, onClick: () => run(calibrationCancel), children: t("Discard") })] })] })) : (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsxs("div", { children: [status.saved ? "A saved calibration is in use." : "Using the driver defaults.", " Start walks each stick and trigger to its edge and back. The controller is paused for Steam while it runs; Cancel works by touch."] }), SP_JSX.jsx(LiveBars, { live: status.live }), SP_JSX.jsxs(DFL.Focusable, { style: { display: "flex", gap: "8px", marginTop: "12px" }, children: [SP_JSX.jsx(DFL.DialogButton, { disabled: busy, onClick: () => run(calibrationStart), children: t("Start") }), SP_JSX.jsx(DFL.DialogButton, { disabled: busy, onClick: () => run(calibrationReset), children: t("Reset to Defaults") }), SP_JSX.jsx(DFL.DialogButton, { disabled: busy, onClick: () => closeModal?.(), children: t("Close") })] })] })), error ? SP_JSX.jsx("div", { style: { marginTop: "8px", color: "#ff8080" }, children: error }) : null] }));
}
function Calibration() {
    // Hidden where the gamepad driver has no calibration parameters (an AYANEO or KONKR pad).
    const [available, setAvailable] = SP_REACT.useState(null);
    SP_REACT.useEffect(() => {
        calibrationStatus()
            .then((status) => setAvailable(status.available))
            .catch(() => setAvailable(false));
    }, []);
    if (!available)
        return null;
    return (SP_JSX.jsxs(DFL.PanelSection, { title: t("CALIBRATION"), children: [SP_JSX.jsx(DFL.Field, { label: t("Sticks and triggers"), description: t("Stick centre and range, trigger travel") }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", onClick: () => DFL.showModal(SP_JSX.jsx(CalibrationModal, {})), children: t("Calibrate Controller") }) })] }));
}

// SliderField has only onChange, so commits are debounced. The pending value lives in
// a ref so the unmount flush always sees the latest edit, not a stale first-render one.
const COMMIT_DELAY = 350;
// Hardware brightness is 0-255; the slider shows percent so it reads like the other two.
const briToPercent = (bri) => Math.round((bri / 255) * 100);
const percentToBri = (percent) => Math.round((percent / 100) * 255);
function ColorControls({ zone, hsv, brightness, onCommit }) {
    const [hue, saturation] = hsv;
    const [localH, setLocalH] = SP_REACT.useState(hsv[0]);
    const [localS, setLocalS] = SP_REACT.useState(hsv[1]);
    const [localBri, setLocalBri] = SP_REACT.useState(brightness);
    const pending = SP_REACT.useRef(null);
    const onCommitRef = SP_REACT.useRef(onCommit);
    onCommitRef.current = onCommit;
    // A commit response landing mid-drag would otherwise snap the slider backwards.
    SP_REACT.useEffect(() => { if (!pending.current)
        setLocalH(hsv[0]); }, [hue]);
    SP_REACT.useEffect(() => { if (!pending.current)
        setLocalS(hsv[1]); }, [saturation]);
    SP_REACT.useEffect(() => { if (!pending.current)
        setLocalBri(brightness); }, [brightness]);
    const schedule = (h, s, bri) => {
        setLocalH(h);
        setLocalS(s);
        setLocalBri(bri);
        pending.current = { hsv: [h, s, 100], bri };
    };
    SP_REACT.useEffect(() => {
        if (pending.current === null)
            return;
        const snapshot = pending.current;
        const timer = window.setTimeout(() => {
            pending.current = null;
            onCommitRef.current(snapshot.hsv, snapshot.bri);
        }, COMMIT_DELAY);
        return () => window.clearTimeout(timer);
    }, [localH, localS, localBri]);
    // QAM unmounts on close; flush any edit still in the debounce window.
    SP_REACT.useEffect(() => () => {
        if (pending.current !== null) {
            const snapshot = pending.current;
            pending.current = null;
            onCommitRef.current(snapshot.hsv, snapshot.bri);
        }
    }, []);
    const setHue = (h) => schedule(h, localS, localBri);
    const setSaturation = (s) => schedule(localH, s, localBri);
    const setBrightness = (b) => schedule(localH, localS, b);
    return (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.SliderField, { label: t("Hue"), value: localH, min: 0, max: 359, step: 1, showValue: true, validValues: "range", valueSuffix: "\u00B0", bottomSeparator: "thick", className: `steamling-led-${zone}-h`, onChange: setHue }) }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.SliderField, { label: t("Saturation"), value: localS, min: 0, max: 100, step: 1, showValue: true, validValues: "range", valueSuffix: "%", bottomSeparator: "thick", className: `steamling-led-${zone}-s`, onChange: setSaturation }) }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.SliderField, { label: t("Brightness"), value: briToPercent(localBri), min: 0, max: 100, step: 1, showValue: true, validValues: "range", valueSuffix: "%", bottomSeparator: "thick", className: `steamling-led-${zone}-v`, onChange: (percent) => setBrightness(percentToBri(percent)) }) }), SP_JSX.jsx("style", { children: `
        .steamling-led-${zone}-h .${DFL.gamepadSliderClasses.SliderTrack} {
          background: linear-gradient(to right,
            hsl(0,100%,50%), hsl(60,100%,50%), hsl(120,100%,50%),
            hsl(180,100%,50%), hsl(240,100%,50%), hsl(300,100%,50%), hsl(360,100%,50%)) !important;
          --left-track-color: #0000 !important;
          --colored-toggles-main-color: #0000 !important;
        }
        .steamling-led-${zone}-s .${DFL.gamepadSliderClasses.SliderTrack} {
          background: linear-gradient(to right, hsl(0,0%,100%), hsl(${localH},100%,50%)) !important;
          --left-track-color: #0000 !important;
          --colored-toggles-main-color: #0000 !important;
        }
        .steamling-led-${zone}-v .${DFL.gamepadSliderClasses.SliderTrack} {
          background: linear-gradient(to right, hsl(0,0%,0%), hsl(${localH},${localS}%,50%)) !important;
          --left-track-color: #0000 !important;
          --colored-toggles-main-color: #0000 !important;
        }
      ` })] }));
}

const STRENGTHS = [25, 50, 75, 100];
function Rumble() {
    const [rumble, setRumbleState] = SP_REACT.useState(null);
    const [error, setError] = SP_REACT.useState("");
    const timer = SP_REACT.useRef(undefined);
    SP_REACT.useEffect(() => {
        rumbleStatus().then(setRumbleState).catch((err) => setError(String(err)));
    }, []);
    if (!rumble || (!rumble.canSwitch && !rumble.canScale))
        return null;
    // Shown at once, written once the slider settles: dragging it fires onChange per notch.
    const save = (enabled, strength) => {
        setError("");
        setRumbleState({ ...rumble, enabled, strength });
        window.clearTimeout(timer.current);
        timer.current = window.setTimeout(() => {
            setRumble(enabled, strength)
                .then(setRumbleState)
                .catch((err) => setError(String(err)));
        }, 300);
    };
    const index = Math.max(0, STRENGTHS.indexOf(rumble.strength));
    return (SP_JSX.jsxs(DFL.PanelSection, { title: t("RUMBLE"), children: [rumble.canSwitch ? (SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ToggleField, { label: t("Enable rumble"), checked: rumble.enabled, onChange: (on) => save(on, rumble.strength) }) })) : null, rumble.canScale ? (SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.SliderField, { label: t("Strength"), value: index, min: 0, max: STRENGTHS.length - 1, step: 1, notchCount: STRENGTHS.length, notchLabels: STRENGTHS.map((pct, i) => ({ notchIndex: i, label: `${pct}%` })), notchTicksVisible: true, disabled: rumble.canSwitch && !rumble.enabled, onChange: (i) => save(rumble.enabled, STRENGTHS[i] ?? 100) }) })) : null, error ? SP_JSX.jsx("div", { className: "steamling-note", children: error }) : null] }));
}

const deadzones = [50, 75, 100, 150, 200, 300];
const outers = [100, 95, 90, 85, 80];
function Stick({ label, stick, value, save }) {
    const dzOptions = deadzones.map((pct) => ({
        data: pct,
        label: pct === 100 ? t("Calibrated (100%)") : pct < 100 ? t("Smaller ({pct}%)", { pct }) : t("Bigger ({pct}%)", { pct }),
    }));
    const outerOptions = outers.map((pct) => ({
        data: pct,
        label: pct === 100 ? t("At the edge") : t("At {pct}% of the way", { pct }),
    }));
    return (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx(SelectEdit, { label: t("{stick}: dead zone", { stick: label }), value: value.deadzone, options: dzOptions, onChange: (pct) => save(stick, { ...value, deadzone: Number(pct) }) }), SP_JSX.jsx(SelectEdit, { label: t("{stick}: full tilt", { stick: label }), value: value.outer, options: outerOptions, onChange: (pct) => save(stick, { ...value, outer: Number(pct) }) })] }));
}
function StickResponse() {
    const [status, setStatus] = SP_REACT.useState(null);
    const [error, setError] = SP_REACT.useState("");
    SP_REACT.useEffect(() => {
        tuningStatus().then(setStatus).catch((err) => setError(String(err)));
    }, []);
    if (!status?.available)
        return null;
    const save = (stick, next) => {
        setError("");
        setStatus({ ...status, [stick]: next });
        setTuning(stick, next.deadzone, next.outer)
            .then(setStatus)
            .catch((err) => setError(String(err)));
    };
    return (SP_JSX.jsxs(DFL.PanelSection, { title: t("STICK RESPONSE"), children: [SP_JSX.jsx(Stick, { label: t("Left stick"), stick: "left", value: status.left, save: save }), SP_JSX.jsx(Stick, { label: t("Right stick"), stick: "right", value: status.right, save: save }), SP_JSX.jsx("div", { className: "steamling-note", children: error ||
                    t("Dead zone: how far a stick moves before it registers, relative to calibration. Full tilt: how far you push to reach 100%. Applies everywhere, kept across reboots. Steam Input adds per-game curves on top.") })] }));
}

function hsvToRgb(h, s, v) {
    const hh = ((h % 360) + 360) % 360;
    const ss = Math.max(0, Math.min(100, s)) / 100;
    const vv = Math.max(0, Math.min(100, v)) / 100;
    const c = vv * ss;
    const x = c * (1 - Math.abs(((hh / 60) % 2) - 1));
    const m = vv - c;
    let r = 0;
    let g = 0;
    let b = 0;
    if (hh < 60)
        [r, g, b] = [c, x, 0];
    else if (hh < 120)
        [r, g, b] = [x, c, 0];
    else if (hh < 180)
        [r, g, b] = [0, c, x];
    else if (hh < 240)
        [r, g, b] = [0, x, c];
    else if (hh < 300)
        [r, g, b] = [x, 0, c];
    else
        [r, g, b] = [c, 0, x];
    return [Math.round((r + m) * 255), Math.round((g + m) * 255), Math.round((b + m) * 255)];
}
function rgbToHsv(r, g, b) {
    const rr = r / 255;
    const gg = g / 255;
    const bb = b / 255;
    const max = Math.max(rr, gg, bb);
    const min = Math.min(rr, gg, bb);
    const delta = max - min;
    let h = 0;
    let s = 0;
    const v = max;
    if (delta !== 0) {
        s = delta / max;
        if (max === rr)
            h = ((gg - bb) / delta + (gg < bb ? 6 : 0)) / 6;
        else if (max === gg)
            h = ((bb - rr) / delta + 2) / 6;
        else
            h = ((rr - gg) / delta + 4) / 6;
    }
    return [Math.round(h * 360), Math.round(s * 100), Math.round(v * 100)];
}

// Stored RGB holds the full-value color; the kernel multicolor class scales each
// channel by brightness/max_brightness, so dimming is linear and the color survives.
function commit(side, hsv, brightness, setConfig, reload) {
    const [r, g, b] = hsvToRgb(hsv[0], hsv[1], 100);
    setLed(side, r, g, b, brightness)
        .then((next) => setConfig((cur) => (cur ? { ...cur, led: next } : cur)))
        .catch(() => reload());
}
function sideHsv(side) {
    return rgbToHsv(side.r, side.g, side.b);
}
function Controller(props) {
    return (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx(Calibration, {}), SP_JSX.jsx(StickResponse, {}), SP_JSX.jsx(BackPaddles, {}), SP_JSX.jsx(Rumble, {}), props.config.led.available && SP_JSX.jsx(StickLights, { ...props })] }));
}
function StickLights({ config, setConfig, reload }) {
    const led = config.led;
    const leftHsv = sideHsv(led.left);
    const rightHsv = sideHsv(led.right);
    const commitLeft = (hsv, brightness) => commit("left", hsv, brightness, setConfig, reload);
    const commitRight = (hsv, brightness) => commit("right", hsv, brightness, setConfig, reload);
    const commitBoth = (hsv, brightness) => commit("both", hsv, brightness, setConfig, reload);
    return (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsxs(DFL.PanelSection, { title: t("STICK LIGHTS"), children: [SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ToggleField, { label: t("Enable"), checked: led.enabled, onChange: (value) => setLedEnabled(value)
                                .then((next) => setConfig((cur) => (cur ? { ...cur, led: next } : cur)))
                                .catch(() => reload()) }) }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ToggleField, { label: t("Link Left & Right"), description: t("Match both sticks to the same color."), checked: led.linked, disabled: !led.enabled, onChange: (value) => setLedLinked(value)
                                .then((next) => setConfig((cur) => (cur ? { ...cur, led: next } : cur)))
                                .catch(() => reload()) }) }), led.sidesAvailable && (SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ToggleField, { label: t("Side Lights"), description: t("Match the side lighting to the sticks."), checked: led.sides, disabled: !led.enabled, onChange: (value) => setLedSides(value)
                                .then((next) => setConfig((cur) => (cur ? { ...cur, led: next } : cur)))
                                .catch(() => reload()) }) }))] }), led.enabled && (led.linked ? (SP_JSX.jsx(DFL.PanelSection, { title: t("BOTH STICKS"), children: SP_JSX.jsx(ColorControls, { zone: "both", hsv: leftHsv, brightness: led.left.brightness, onCommit: commitBoth }) })) : (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx(DFL.PanelSection, { title: t("LEFT STICK"), children: SP_JSX.jsx(ColorControls, { zone: "left", hsv: leftHsv, brightness: led.left.brightness, onCommit: commitLeft }) }), SP_JSX.jsx(DFL.PanelSection, { title: t("RIGHT STICK"), children: SP_JSX.jsx(ColorControls, { zone: "right", hsv: rightHsv, brightness: led.right.brightness, onCommit: commitRight }) })] })))] }));
}

// Panels leave the factory a touch fast or slow, and emulators that pace to the display drift
// against their audio. steamling-panel-calibration measures the running refresh rate and trims the
// panel's frame length until it sits on the nominal rate; the result is kept across reboots.
function PanelModal({ initial, onChange, closeModal }) {
    const [status, setStatus] = SP_REACT.useState(initial);
    const [busy, setBusy] = SP_REACT.useState(initial.running);
    const [error, setError] = SP_REACT.useState("");
    const busyRef = SP_REACT.useRef(busy);
    busyRef.current = busy;
    const run = async (action) => {
        if (busyRef.current)
            return;
        setBusy(true);
        setError("");
        try {
            const next = await action();
            setStatus(next);
            onChange(next);
        }
        catch (e) {
            setError(String(e));
        }
        finally {
            setBusy(false);
        }
    };
    const result = status.result;
    return (SP_JSX.jsxs(DFL.ModalRoot, { closeModal: busy ? undefined : closeModal, bDisableBackgroundDismiss: busy, children: [SP_JSX.jsx("div", { style: { fontSize: "20px", fontWeight: "bold", marginBottom: "8px" }, children: t("Display Refresh Calibration") }), SP_JSX.jsx("div", { children: busy
                    ? "Measuring… this takes up to a minute. Leave the device on this screen until it finishes."
                    : `${status.saved ? "A saved calibration is in use." : "Using the panel's factory timing."} Calibrate measures the refresh rate and trims it to exactly the nominal rate, which keeps emulator audio and video in step.` }), result && !busy ? (SP_JSX.jsx("div", { style: { marginTop: "8px" }, children: `${result.rate} Hz: measured ${result.before.toFixed(2)} Hz, now ${result.after.toFixed(2)} Hz.` })) : null, SP_JSX.jsxs(DFL.Focusable, { style: { display: "flex", gap: "8px", marginTop: "12px" }, children: [SP_JSX.jsx(DFL.DialogButton, { disabled: busy, onClick: () => run(panelCalibrate), children: busy ? "Calibrating…" : "Calibrate" }), SP_JSX.jsx(DFL.DialogButton, { disabled: busy || !status.saved, onClick: () => run(panelReset), children: t("Reset to Factory") }), SP_JSX.jsx(DFL.DialogButton, { disabled: busy, onClick: () => closeModal?.(), children: t("Close") })] }), error ? SP_JSX.jsx("div", { style: { marginTop: "8px", color: "#ff8080" }, children: error }) : null] }));
}
function PanelCalibration() {
    const [status, setStatus] = SP_REACT.useState(null);
    const visible = useQamVisible();
    // One cheap sysfs read per menu open; panels without the attributes never show the section.
    SP_REACT.useEffect(() => {
        if (!visible)
            return;
        let cancelled = false;
        panelStatus()
            .then((next) => { if (!cancelled)
            setStatus(next); })
            .catch(() => { });
        return () => { cancelled = true; };
    }, [visible]);
    if (!status?.available)
        return null;
    return (SP_JSX.jsxs(DFL.PanelSection, { title: t("DISPLAY"), children: [SP_JSX.jsx(DFL.Field, { label: t("Refresh rate"), description: status.saved ? "Calibrated" : "Factory timing" }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", onClick: () => DFL.showModal(SP_JSX.jsx(PanelModal, { initial: status, onChange: setStatus })), children: t("Calibrate Display") }) })] }));
}

function PerformanceOverlay() {
    const [overlay, setOverlayState] = SP_REACT.useState(null);
    const [error, setError] = SP_REACT.useState("");
    const busy = SP_REACT.useRef(false);
    const visible = useQamVisible();
    // Re-read on every open: Steam's own Performance Overlay setting writes the same file.
    SP_REACT.useEffect(() => {
        if (!visible)
            return;
        let cancelled = false;
        overlayStatus()
            .then((next) => {
            if (!cancelled && !busy.current)
                setOverlayState(next);
        })
            .catch(() => { });
        return () => {
            cancelled = true;
        };
    }, [visible]);
    if (!overlay?.available)
        return null;
    const options = [
        { data: "off", label: t("Off") },
        { data: "fps", label: t("FPS only") },
        { data: "compact", label: t("Compact bar: FPS, CPU, GPU, RAM, battery") },
        { data: "detailed", label: t("Detailed: adds clocks, temperatures, power") },
        { data: "full", label: t("Everything") },
    ];
    if (overlay.level === "custom")
        options.push({ data: "custom", label: t("Set from Steam") });
    const change = async (level) => {
        if (busy.current || level === "custom")
            return;
        busy.current = true;
        setError("");
        try {
            setOverlayState(await setOverlay(level));
        }
        catch (err) {
            setError(String(err));
        }
        finally {
            busy.current = false;
        }
    };
    return (SP_JSX.jsxs(DFL.PanelSection, { title: t("PERFORMANCE OVERLAY"), children: [SP_JSX.jsx(SelectEdit, { label: t("Show on screen"), value: overlay.level, options: options, onChange: change }), SP_JSX.jsx("div", { className: "steamling-note", children: error || t("Stays from game to game. Steam's own Performance Overlay setting changes it too, until the next game starts.") })] }));
}

const REFRESH_MS = 2000;
const SHOW_KEY = "steamling-control.monitor";
function remembered() {
    try {
        return window.localStorage.getItem(SHOW_KEY) === "1";
    }
    catch (error) {
        return false;
    }
}
function remember(on) {
    try {
        window.localStorage.setItem(SHOW_KEY, on ? "1" : "0");
    }
    catch (error) {
    }
}
const dash = "–";
function cpuText(stats) {
    const clocks = stats.cpu.clusters.map((c) => `${(c.mhz / 1000).toFixed(1)}`).join(" / ");
    const load = stats.cpu.load === null ? dash : `${stats.cpu.load}%`;
    return t("{load} busy · {clocks} GHz", { load, clocks: clocks || dash });
}
function tempText(stats) {
    const parts = [];
    if (stats.temps.cpu !== undefined)
        parts.push(t("CPU {n}°C", { n: stats.temps.cpu }));
    if (stats.temps.gpu !== undefined)
        parts.push(t("GPU {n}°C", { n: stats.temps.gpu }));
    if (stats.battery?.tempC != null)
        parts.push(t("Battery {n}°C", { n: stats.battery.tempC }));
    return parts.join(" · ") || dash;
}
function batteryText(stats) {
    const b = stats.battery;
    if (!b)
        return dash;
    const pct = b.percent === null ? dash : `${b.percent}%`;
    // Not charging (bypass charging, a charge limit) and Full both mean the charger runs the
    // handheld: the battery isn't the one being drawn from.
    if (b.status === "Not charging" || b.status === "Full")
        return `${pct} · ${t("on external power")}`;
    if (b.watts === null)
        return pct;
    const flow = b.status === "Charging" ? t("charging at {w} W", { w: b.watts }) : t("drawing {w} W", { w: b.watts });
    return `${pct} · ${flow}`;
}
function SystemMonitor() {
    const [show, setShow] = SP_REACT.useState(remembered);
    const [stats, setStats] = SP_REACT.useState(null);
    const visible = useQamVisible();
    // Only while it is switched on and the menu is open: nothing reads these numbers otherwise.
    SP_REACT.useEffect(() => {
        if (!show || !visible)
            return;
        let cancelled = false;
        const tick = () => systemStats()
            .then((next) => {
            if (!cancelled)
                setStats(next);
        })
            .catch(() => { });
        tick();
        const timer = window.setInterval(tick, REFRESH_MS);
        return () => {
            cancelled = true;
            window.clearInterval(timer);
        };
    }, [show, visible]);
    return (SP_JSX.jsxs(DFL.PanelSection, { title: t("SYSTEM MONITOR"), children: [SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ToggleField, { label: t("Show live readings"), description: t("Updates every 2 seconds while this menu is open"), checked: show, onChange: (on) => {
                        setShow(on);
                        remember(on);
                    } }) }), show && stats ? (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx(DFL.Field, { label: t("CPU"), description: cpuText(stats) }), SP_JSX.jsx(DFL.Field, { label: t("GPU"), description: stats.gpu ? t("{mhz} of {max} MHz", { mhz: stats.gpu.mhz, max: stats.gpu.maxMhz }) : dash }), SP_JSX.jsx(DFL.Field, { label: t("Temperature"), description: tempText(stats) }), SP_JSX.jsx(DFL.Field, { label: t("Battery"), description: batteryText(stats) }), SP_JSX.jsx(DFL.Field, { label: t("Memory"), description: stats.memory
                            ? t("{used} of {total} GB", {
                                used: (stats.memory.usedMb / 1024).toFixed(1),
                                total: (stats.memory.totalMb / 1024).toFixed(1),
                            })
                            : dash }), stats.fan ? (SP_JSX.jsx(DFL.Field, { label: t("Fan"), description: stats.fan.rpm !== null ? t("{rpm} RPM", { rpm: stats.fan.rpm }) : t("{n}% speed", { n: stats.fan.percent ?? 0 }) })) : null] })) : null] }));
}

// What's on the screen: the overlay and live readings first, the panel and menu settings after.
function Display() {
    return (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx(PerformanceOverlay, {}), SP_JSX.jsx(SystemMonitor, {}), SP_JSX.jsx(PanelCalibration, {}), SP_JSX.jsx(MenuWidthSetting, {})] }));
}

// Every Steam game and every non-Steam shortcut (emulator tiles, ROM managers, a Windows .exe on
// Proton) launches through steamling-game-launch, which applies the per-game tweaks at launch
// time, so a settings change never has to touch launch options.
// Bare name: Steam runs launch options through a shell with the system PATH (/usr/bin).
const LAUNCHER = "steamling-game-launch";
const COMMAND = "%command%";
// Written by this plugin before the launcher existed; the launcher exports it itself now.
const FEX_TOKEN = /STEAM_COMPAT_FEX_CONFIG=("[^"]*"|\S*)\s*/g;
function getLaunchOptions(appid) {
    return new Promise((resolve) => {
        const apps = window.SteamClient?.Apps;
        if (!apps?.RegisterForAppDetails)
            return resolve(null);
        let registration;
        let timer;
        let done = false;
        const finish = (value) => {
            if (done)
                return;
            done = true;
            if (timer !== undefined)
                window.clearTimeout(timer);
            // Steam may call back before RegisterForAppDetails returns; unregister on a microtask.
            Promise.resolve().then(() => registration?.unregister?.());
            resolve(value);
        };
        timer = window.setTimeout(() => finish(null), 3000);
        try {
            registration = apps.RegisterForAppDetails(Number(appid), (details) => {
                finish(String(details?.strLaunchOptions ?? ""));
            });
        }
        catch (error) {
            finish(null);
        }
    });
}
/** null = already wrapped. Keeps the user's own options around %command%. */
function wrapLaunchOptions(current) {
    const stripped = current.replace(FEX_TOKEN, "").trim();
    if (stripped.includes(LAUNCHER))
        return stripped === current.trim() ? null : stripped;
    if (stripped.includes(COMMAND))
        return stripped.replace(COMMAND, `${LAUNCHER} ${COMMAND}`);
    // Without %command% Steam appends bare options as arguments, so they stay after it.
    return [`${LAUNCHER} ${COMMAND}`, stripped].filter(Boolean).join(" ");
}
/** Bails rather than clobber when the current value can't be read. */
async function ensureLaunchWrapper(appid) {
    const apps = window.SteamClient?.Apps;
    if (!apps?.SetAppLaunchOptions)
        return false;
    const current = await getLaunchOptions(appid);
    if (current === null)
        return false;
    const next = wrapLaunchOptions(current);
    if (next !== null)
        apps.SetAppLaunchOptions(Number(appid), next);
    return true;
}
async function wrapShortcuts(appids) {
    for (const appid of appids)
        await ensureLaunchWrapper(appid);
}
async function wrapAllGames(appids) {
    let next = 0;
    const worker = async () => {
        while (next < appids.length)
            await ensureLaunchWrapper(appids[next++]);
    };
    await Promise.all(Array.from({ length: Math.min(8, appids.length) }, worker));
}
/** New installs get wrapped once their download queues; returns the unregister. */
function registerDownloadWrapper(isGame) {
    const downloads = window.SteamClient?.Downloads;
    if (!downloads?.RegisterForDownloadItems)
        return () => { };
    const pending = new Set();
    let timer;
    const flush = () => {
        timer = undefined;
        const ids = Array.from(pending);
        pending.clear();
        wrapAllGames(ids.filter(isGame));
    };
    // Each queue item is { item_data: [{ appid, ... }] }: the appids live in item_data.
    const handle = downloads.RegisterForDownloadItems((_paused, items) => {
        if (!Array.isArray(items))
            return;
        for (const item of items) {
            for (const entry of Object.values(item?.item_data || {})) {
                const appid = String(entry?.appid ?? "");
                if (appid && appid !== "0")
                    pending.add(appid);
            }
        }
        if (timer === undefined)
            timer = window.setTimeout(flush, 1500);
    });
    return () => {
        if (timer !== undefined)
            window.clearTimeout(timer);
        try {
            handle?.unregister?.();
        }
        catch (error) {
        }
    };
}

// Drives the same state as Steam's own per-game compatibility dropdown (SpecifyCompatTool +
// app details), so never store a shadow copy: the two UIs stay in sync by construction.

// Steam's tool list is only reachable through its react-query hook, which throws
// without Steam's QueryClient in context; a throwaway root under Steam's provider
// works from any tree (QAM panel, modals, import flow).
const steam = {
    hook: null,
    provider: null,
    client: null,
    createRoot: null,
};
function findSteam() {
    steam.hook || (steam.hook = DFL.findModuleExport((e) => typeof e === "function" && e.toString().includes("Failed to fetch available compat tools")));
    steam.provider || (steam.provider = DFL.findModuleExport((e) => {
        if (typeof e !== "function")
            return false;
        const src = e.toString();
        return src.length < 400 && /\.mount\(\)/.test(src) && /unmount\(\)/.test(src) && /children/.test(src);
    }));
    steam.client || (steam.client = DFL.findModuleExport((e) => e && typeof e === "object" && typeof e.getQueryCache === "function" && typeof e.invalidateQueries === "function"));
    steam.createRoot || (steam.createRoot = DFL.findModule((m) => typeof m?.createRoot === "function")?.createRoot);
    return !!(steam.hook && steam.provider && steam.client && steam.createRoot);
}
class ProbeBoundary extends SP_REACT.Component {
    constructor() {
        super(...arguments);
        this.state = { failed: false };
    }
    static getDerivedStateFromError() {
        return { failed: true };
    }
    componentDidCatch(error) {
        this.props.onError(error);
    }
    render() {
        return this.state.failed ? null : this.props.children;
    }
}
function steamCompatTools(appid) {
    return new Promise((resolve) => {
        let root = null;
        const finish = (tools) => {
            clearTimeout(timer);
            resolve(tools);
            setTimeout(() => root?.unmount(), 0);
        };
        const timer = setTimeout(() => finish([]), 10000);
        const Probe = () => {
            const [query] = steam.hook(Number(appid));
            if (query.status === "success")
                finish(fromSteam(query.data));
            else if (query.status === "error")
                finish([]);
            return null;
        };
        try {
            root = steam.createRoot(document.createElement("div"));
            root.render(SP_REACT.createElement(ProbeBoundary, { onError: () => finish([]) }, SP_REACT.createElement(steam.provider, { client: steam.client }, SP_REACT.createElement(Probe))));
        }
        catch {
            finish([]);
        }
    });
}
function fromSteam(data) {
    return (data?.tools ?? [])
        .filter((tool) => !tool.is_incompatible)
        .map((tool) => ({ name: String(tool.name ?? ""), label: String(tool.display_name || tool.name || "") }))
        .filter((tool) => tool.name);
}
async function availableCompatTools(appid) {
    const apps = window.SteamClient?.Apps;
    try {
        if (apps?.GetAvailableCompatTools) {
            const tools = await apps.GetAvailableCompatTools(Number(appid));
            if (!Array.isArray(tools))
                return [];
            return tools
                .map((tool) => ({
                name: String(tool?.strToolName ?? ""),
                label: String(tool?.strDisplayName ?? tool?.strToolName ?? ""),
            }))
                .filter((tool) => tool.name);
        }
        return findSteam() ? await steamCompatTools(appid) : [];
    }
    catch {
        return [];
    }
}
/** Live view of the game's current tool; fires again when it changes anywhere (incl. Steam's UI). */
function registerForCompatTool(appid, onChange) {
    const apps = window.SteamClient?.Apps;
    if (!apps?.RegisterForAppDetails)
        return () => { };
    const registration = apps.RegisterForAppDetails(Number(appid), (details) => {
        onChange(String(details?.strCompatToolName ?? ""));
    });
    return () => registration?.unregister?.();
}
function setCompatTool(appid, tool) {
    window.SteamClient?.Apps?.SpecifyCompatTool?.(Number(appid), tool);
    // A shortcut picked up after the load-time sweep still gets the launcher.
    if (tool && Number(appid) >= 0x80000000)
        ensureLaunchWrapper(appid);
}
/** Resolve an imported Proton pick against this device's tools. Unknown ARM-named tools
 *  fall back to the cachy ARM Proton; unknown x86-named ones to a Proton 11. */
function resolveCompatTool(wanted, tools) {
    if (!wanted)
        return { tool: "", fallback: false };
    if (tools.some((tool) => tool.name === wanted))
        return { tool: wanted, fallback: false };
    const haystack = (tool) => `${tool.name} ${tool.label}`;
    const isArm = /arm/i.test(wanted);
    const fallback = isArm
        ? tools.find((tool) => /cachy/i.test(haystack(tool)) && !/x86/i.test(haystack(tool)))
        : tools.find((tool) => /(^|\D)11(\D|$)/.test(haystack(tool)) && !/arm|cachy/i.test(haystack(tool)));
    return { tool: fallback?.name || "", fallback: true };
}

function ExportNameModal({ game, base, onDone, closeModal }) {
    const [value, setValue] = SP_REACT.useState(base);
    const [busy, setBusy] = SP_REACT.useState(false);
    const overwriting = value.trim() === base;
    const submit = async () => {
        if (busy || !value.trim())
            return;
        setBusy(true);
        try {
            const result = await exportConfig(game.appid, game.name, value.trim(), true);
            onDone(result.path);
        }
        catch (error) {
            toaster.toast({ title: t("Export failed"), body: String(error) });
        }
        closeModal?.();
    };
    return (SP_JSX.jsx(DFL.ConfirmModal, { strTitle: t("Config Already Exists"), strDescription: `${base}.steamling.json exists. Change the name to save a new config (e.g. ${base}-2 or ${base}-fast), or keep it to overwrite.`, strOKButtonText: busy ? "Saving…" : overwriting ? "Overwrite" : "Save New", bOKDisabled: busy || !value.trim(), onCancel: () => closeModal?.(), onOK: submit, children: SP_JSX.jsx(DFL.TextField, { label: t("Name"), value: value, disabled: busy, onChange: (event) => setValue(event.target.value) }) }));
}
function ImportModal({ path, preview, game, onDone, closeModal }) {
    const profiles = preview.games;
    const [source, setSource] = SP_REACT.useState(profiles[0]?.appid || "");
    const [busy, setBusy] = SP_REACT.useState(false);
    const from = [preview.device, preview.exported].filter(Boolean).join(", ");
    const profileOptions = profiles.map((profile) => ({ data: profile.appid, label: profile.name || profile.appid }));
    const submit = async () => {
        if (busy || !source)
            return;
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
                }
                else {
                    toaster.toast({ title: t("Proton pick skipped"), body: `${result.protonTool} not available here` });
                }
            }
            toaster.toast({ title: t("Config applied"), body: game.name || game.appid });
        }
        catch (error) {
            toaster.toast({ title: t("Import failed"), body: String(error) });
        }
        closeModal?.();
        onDone();
    };
    return (SP_JSX.jsx(DFL.ConfirmModal, { strTitle: t("Import Game Config"), strDescription: (from ? `Exported from ${from}. ` : "") + `Settings for ${game.name || game.appid} will be overwritten.`, strOKButtonText: busy ? "Applying…" : "Apply", bOKDisabled: busy || !source, onCancel: () => closeModal?.(), onOK: submit, children: profiles.length > 1 ? (SP_JSX.jsx(SelectEdit, { label: t("Profile"), value: source, options: profileOptions, onChange: (id) => setSource(String(id)) })) : (SP_JSX.jsxs("div", { className: "steamling-note", children: ["Profile: ", profiles[0]?.name || profiles[0]?.appid] })) }));
}
/** Per-game config export/import; rendered only when a game's per-game settings are enabled. */
function ConfigSection({ game, reload }) {
    const doExport = async () => {
        try {
            const result = await exportConfig(game.appid, game.name || "", "", false);
            if (result.exists) {
                DFL.showModal(SP_JSX.jsx(ExportNameModal, { game: { appid: game.appid, name: game.name || "" }, base: result.base, onDone: (path) => toaster.toast({ title: t("Game config exported"), body: path }) }));
                return;
            }
            toaster.toast({ title: t("Game config exported"), body: result.path });
        }
        catch (error) {
            toaster.toast({ title: t("Export failed"), body: String(error) });
        }
    };
    const doImport = async () => {
        let path = "";
        try {
            const dir = await configDir().catch(() => "/home/deck");
            // 0 = FileSelectionType.FILE (same const-enum note as AddGame).
            const picked = await openFilePicker(0, dir, true, true);
            path = picked?.path || "";
        }
        catch (error) {
            return; // picker closed without a selection
        }
        if (!path)
            return;
        try {
            const preview = await readConfig(path);
            DFL.showModal(SP_JSX.jsx(ImportModal, { path: path, preview: preview, game: game, onDone: reload }));
        }
        catch (error) {
            toaster.toast({ title: t("Import failed"), body: String(error) });
        }
    };
    return (SP_JSX.jsxs(DFL.PanelSection, { title: t("CONFIG"), children: [SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", onClick: doExport, children: t("Export Game Config") }) }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", onClick: doImport, children: t("Import Game Config") }) }), SP_JSX.jsx("div", { className: "steamling-note", children: t("Per-game tweaks and Proton pick; fan settings and defaults stay local") })] }));
}

function clone(obj) {
    return JSON.parse(JSON.stringify(obj));
}
// Decimal units, the way Steam and file managers show sizes.
function formatBytes(bytes) {
    if (bytes < 1e6)
        return `${Math.max(0, Math.round(bytes / 1e3))} KB`;
    if (bytes < 1e9)
        return `${Math.round(bytes / 1e6)} MB`;
    return `${(bytes / 1e9).toFixed(1)} GB`;
}

function ShaderCache({ appid, name, running }) {
    const [info, setInfo] = SP_REACT.useState(null);
    const [busy, setBusy] = SP_REACT.useState(false);
    const [error, setError] = SP_REACT.useState("");
    const busyRef = SP_REACT.useRef(false);
    busyRef.current = busy;
    const visible = useQamVisible();
    SP_REACT.useEffect(() => {
        if (!visible || !appid)
            return;
        let cancelled = false;
        setInfo(null);
        setError("");
        cacheInfo(appid)
            .then((next) => {
            if (!cancelled)
                setInfo(next);
        })
            .catch((err) => {
            if (!cancelled)
                setError(String(err));
        });
        return () => {
            cancelled = true;
        };
    }, [appid, visible]);
    const clear = async () => {
        if (busyRef.current)
            return;
        setBusy(true);
        setError("");
        try {
            setInfo(await clearCache(appid));
        }
        catch (err) {
            setError(String(err));
        }
        finally {
            setBusy(false);
        }
    };
    const size = info ? formatBytes(info.bytes) : "…";
    const description = () => {
        if (error)
            return error;
        if (running)
            return t("Close the game to clear it.");
        if (info && info.bytes === 0)
            return t("Nothing cached yet.");
        return t("Compiled shaders for this game. Clearing fixes some graphics glitches after a driver or game update; the game stutters a little while it rebuilds them.");
    };
    return (SP_JSX.jsx(DFL.PanelSection, { title: t("SHADER CACHE"), children: SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", description: description(), disabled: busy || running || !info || info.bytes === 0, onClick: () => DFL.showModal(SP_JSX.jsx(DFL.ConfirmModal, { strTitle: t("Clear Shader Cache"), strDescription: t("Delete the {size} of compiled shaders kept for {name}? The game builds them again as it runs.", { size, name }), strOKButtonText: t("Clear"), onOK: clear })), children: busy ? t("Clearing…") : t("Clear Shader Cache ({size})", { size }) }) }) }));
}

// Audio buffer (PULSE_LATENCY_MSEC): absorbs FEX-mixer overruns (SFX-burst crackle) at the
// cost of audio latency — keep rhythm games on Game default.
const audioLatencyOptions = [
    { data: "", label: t("Game default") },
    { data: "60", label: t("60 ms") },
    { data: "90", label: t("90 ms") },
    { data: "120", label: t("120 ms") },
];
const fanOptions = [
    { data: "quiet", label: t("Quiet") },
    { data: "moderate", label: t("Moderate") },
    { data: "performance", label: t("Performance") },
];
const lavdOptions = [
    { data: "autopilot", label: t("Autopilot") },
    { data: "performance", label: t("Performance") },
];
const globalChoice = { data: "", label: t("Use global") };
function EnvVarsModal({ initial, onSave, closeModal }) {
    const [value, setValue] = SP_REACT.useState(initial);
    return (SP_JSX.jsx(DFL.ConfirmModal, { strTitle: t("Environment Variables"), strDescription: 'Space-separated KEY=VALUE pairs; quote values with spaces, e.g. DXVK_CONFIG="dxgi.customDeviceDesc = GTX 480". Steam launch options win over these.', strOKButtonText: t("Save"), onCancel: () => closeModal?.(), onOK: () => {
            onSave(value.trim());
            closeModal?.();
        }, children: SP_JSX.jsx(DFL.TextField, { label: t("Variables"), value: value, onChange: (event) => setValue(event.target.value) }) }));
}
function EnvVarsButton({ value, onSave }) {
    return (SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", description: value ? value : "None set", onClick: () => DFL.showModal(SP_JSX.jsx(EnvVarsModal, { initial: value, onSave: onSave })), children: t("Environment Variables") }) }));
}
function XaliaToggle({ values, patch }) {
    return (SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ToggleField, { label: t("Disable Xalia"), description: t("Proton's controller-navigation helper; costs CPU in every game"), checked: values.disableXalia !== false, onChange: (checked) => patch({ disableXalia: checked }) }) }));
}
/** Applies live: the backend re-syncs the running game's touchscreen on every save. */
function TouchField({ values, patch }) {
    return (SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ToggleField, { label: t("Disable Touchscreen"), description: t("While the game is running, to stop stray touches"), checked: values.touchDisabled === true, onChange: (on) => patch({ touchDisabled: on }) }) }));
}
/** What the handheld has; an older backend that doesn't say counts as having everything. */
function hw(config) {
    return { fan: true, scheduler: true, touchscreen: true, padSwitch: true, ...(config.hardware || {}) };
}
/** Per-game fan/scheduler overrides ("" = follow the global mode); only the ones this handheld has. */
function PerfFields({ config, values, patch }) {
    const has = hw(config);
    const perGameFan = [globalChoice, ...fanOptions];
    const perGameLavd = [globalChoice, ...lavdOptions];
    const fanValue = perGameFan.some((option) => option.data === String(values.fanMode ?? "")) ? String(values.fanMode ?? "") : "";
    const lavdValue = perGameLavd.some((option) => option.data === String(values.lavdMode ?? "")) ? String(values.lavdMode ?? "") : "";
    return (SP_JSX.jsxs(SP_JSX.Fragment, { children: [has.scheduler ? SP_JSX.jsx(SelectEdit, { label: t("CPU Scheduler"), value: lavdValue, options: perGameLavd, onChange: (id) => patch({ lavdMode: id }) }) : null, has.fan ? SP_JSX.jsx(SelectEdit, { label: t("Fan Curve"), value: fanValue, options: perGameFan, onChange: (id) => patch({ fanMode: id }) }) : null] }));
}
/** Applies live, like the touchscreen: the backend switches the pad when the game starts or stops. */
function GamepadTypeField({ values, patch }) {
    const options = [
        { data: "", label: t("Steam Deck (default)") },
        { data: "xb360", label: t("Xbox 360") },
        { data: "xbox-series", label: t("Xbox Series") },
        { data: "ds5", label: t("DualSense") },
    ];
    const stored = String(values.gamepadType ?? "");
    const value = options.some((option) => option.data === stored) ? stored : "";
    return (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx(SelectEdit, { label: t("Controller Type"), value: value, options: options, onChange: (id) => patch({ gamepadType: id }) }), SP_JSX.jsx("div", { className: "steamling-note", children: t("What the game sees while it runs. Only matters with Steam Input turned off for the game.") })] }));
}
/** The per-game tweak controls, shared by the Games tab and the library context-menu modal. */
function TweakFields({ config, appid, values, patch }) {
    // Proton pick is Steam's own per-game compat setting (see lib/compat.ts) — read live and
    // written straight back to Steam, so it mirrors the game-properties dropdown both ways.
    const [compatTools, setCompatTools] = SP_REACT.useState([]);
    const [currentTool, setCurrentTool] = SP_REACT.useState("");
    SP_REACT.useEffect(() => {
        setCompatTools([]);
        setCurrentTool("");
        if (!appid)
            return;
        let live = true;
        availableCompatTools(appid).then((tools) => {
            if (live)
                setCompatTools(tools);
        });
        const unregister = registerForCompatTool(appid, (tool) => {
            if (live)
                setCurrentTool(tool);
        });
        return () => {
            live = false;
            unregister();
        };
    }, [appid]);
    const compatOptions = [
        { data: "", label: t("Steam default") },
        ...compatTools.map((tool) => ({ data: tool.name, label: tool.label })),
    ];
    const compatValue = compatOptions.some((option) => option.data === currentTool) ? currentTool : "";
    const presets = config.fexProfiles || {};
    const storedProfile = values.fexProfile;
    const fexValue = storedProfile && presets[storedProfile] ? storedProfile : "default";
    const fexOptions = Object.entries(presets).map(([id, profile]) => ({ data: id, label: profile.label }));
    const storedLatency = String(values.audioLatency ?? "");
    const audioValue = audioLatencyOptions.some((option) => option.data === storedLatency) ? storedLatency : "";
    const mesaOptions = [{ data: "", label: t("System default") }, ...(config.mesaVersions || [])];
    const storedMesa = String(values.mesaVersion ?? "");
    const mesaValue = mesaOptions.some((option) => option.data === storedMesa) ? storedMesa : "";
    return (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx(SelectEdit, { label: t("Proton Version"), value: compatValue, options: compatOptions, onChange: (name) => {
                    setCurrentTool(String(name));
                    setCompatTool(appid, String(name));
                } }), SP_JSX.jsx(SelectEdit, { label: t("FEX Preset"), value: fexValue, options: fexOptions, onChange: (id) => patch({ fexProfile: id }) }), SP_JSX.jsx(SelectEdit, { label: t("Audio Buffer"), value: audioValue, options: audioLatencyOptions, onChange: (id) => patch({ audioLatency: id }) }), (config.mesaVersions || []).length > 0 ? (SP_JSX.jsx(SelectEdit, { label: t("Mesa Version"), value: mesaValue, options: mesaOptions, onChange: (id) => patch({ mesaVersion: id }) })) : null, SP_JSX.jsx(XaliaToggle, { values: values, patch: patch }), hw(config).touchscreen ? SP_JSX.jsx(TouchField, { values: values, patch: patch }) : null, hw(config).padSwitch ? SP_JSX.jsx(GamepadTypeField, { values: values, patch: patch }) : null, SP_JSX.jsx(EnvVarsButton, { value: String(values.envVars ?? ""), onSave: (next) => patch({ envVars: next }) })] }));
}

// A suggestion made on another handheld can name a fan or scheduler this one doesn't have.
function usable(config, settings) {
    const has = hw(config);
    const out = { ...settings };
    if (!has.fan)
        delete out.fanMode;
    if (!has.scheduler)
        delete out.lavdMode;
    if (!has.touchscreen)
        delete out.touchDisabled;
    if (!has.padSwitch)
        delete out.gamepadType;
    if (!(config.mesaVersions || []).some((v) => v.data === out.mesaVersion))
        delete out.mesaVersion;
    return out;
}
function describe(config, suggestion) {
    const lines = [];
    const s = usable(config, suggestion.settings);
    const pick = (options, value) => options.find((o) => o.data === String(value))?.label || String(value);
    if (suggestion.proton)
        lines.push(t("Proton: {tool}", { tool: suggestion.proton }));
    if (s.fexProfile)
        lines.push(t("FEX Preset: {value}", { value: config.fexProfiles?.[s.fexProfile]?.label || s.fexProfile }));
    if (s.audioLatency !== undefined)
        lines.push(t("Audio Buffer: {value}", { value: pick(audioLatencyOptions, s.audioLatency) }));
    if (s.mesaVersion)
        lines.push(t("Mesa Version: {value}", { value: s.mesaVersion }));
    if (s.fanMode)
        lines.push(t("Fan Curve: {value}", { value: pick(fanOptions, s.fanMode) }));
    if (s.lavdMode)
        lines.push(t("CPU Scheduler: {value}", { value: pick(lavdOptions, s.lavdMode) }));
    if (s.gamepadType)
        lines.push(t("Controller Type: {value}", { value: s.gamepadType }));
    if (s.disableXalia !== undefined)
        lines.push(s.disableXalia ? t("Xalia off") : t("Xalia on"));
    if (s.touchDisabled)
        lines.push(t("Touchscreen off while playing"));
    if (s.envVars)
        lines.push(t("Environment: {value}", { value: s.envVars }));
    return lines;
}
/** One-tap known-good settings for the selected game, when the list has an entry for it. */
function Suggestion({ config, appid, apply }) {
    const suggestion = config.suggestions?.[appid];
    if (!suggestion)
        return null;
    const lines = describe(config, suggestion);
    return (SP_JSX.jsxs(DFL.PanelSection, { title: t("SUGGESTED SETTINGS"), children: [suggestion.note ? SP_JSX.jsx("div", { className: "steamling-note", children: suggestion.note }) : null, SP_JSX.jsx(DFL.Field, { label: t("Would set"), description: lines.join(" · ") }), suggestion.tested ? SP_JSX.jsx("div", { className: "steamling-note", children: t("Tested on {where}", { where: suggestion.tested }) }) : null, SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", description: t("Turns on per-game settings for this game and fills them in. You can still change anything afterwards."), onClick: () => {
                        apply(usable(config, suggestion.settings));
                        if (suggestion.proton)
                            setCompatTool(appid, suggestion.proton);
                    }, children: t("Use Suggested Settings") }) })] }));
}

function Games({ config, setConfig, reload }) {
    const runtimeGame = config.game;
    // One app-store lookup per game: worth doing once per library change, not on every render.
    const games = SP_REACT.useMemo(() => availableGames(config), [config.installedGames, config.tweaks.games]);
    const targetOptions = SP_REACT.useMemo(() => editTargetOptions(games), [games]);
    const game = config.selectedGame || runtimeGame || null;
    const tweaks = config.tweaks;
    const gameSettings = game?.appid ? tweaks.games[game.appid] || {} : {};
    const editingDefault = !game?.appid;
    const perGameEnabled = !!(game?.appid && gameSettings.enabled === true);
    const values = editingDefault || !perGameEnabled ? tweaks.global : { ...tweaks.global, ...gameSettings };
    const patchSettings = (patch) => {
        setConfig((current) => {
            if (!current)
                return current;
            const next = { ...current, tweaks: clone(current.tweaks) };
            if (editingDefault) {
                Object.assign(next.tweaks.global, patch);
            }
            else if (perGameEnabled) {
                const existing = next.tweaks.games[game.appid] || {};
                next.tweaks.games[game.appid] = { ...existing, enabled: true, name: game.name || "", ...patch };
            }
            return next;
        });
    };
    const setPerGameEnabled = (enabled) => {
        if (!game?.appid)
            return;
        setConfig((current) => {
            if (!current)
                return current;
            const next = { ...current, tweaks: clone(current.tweaks) };
            next.tweaks.games[game.appid] = {
                ...(next.tweaks.games[game.appid] || {}),
                enabled,
                name: game.name || "",
            };
            return next;
        });
    };
    // A suggestion turns per-game settings on and fills them in, in one save.
    const applySuggestion = (settings) => {
        if (!game?.appid)
            return;
        setConfig((current) => {
            if (!current)
                return current;
            const next = { ...current, tweaks: clone(current.tweaks) };
            next.tweaks.games[game.appid] = {
                ...(next.tweaks.games[game.appid] || {}),
                ...settings,
                enabled: true,
                name: game.name || "",
            };
            return next;
        });
    };
    // "" is the explicit Default target, not "nothing selected"; store a sentinel
    // so it doesn't fall back to the running game in the selectedGame derivation.
    const setSelectedGame = (appid) => {
        const id = String(appid);
        if (!id) {
            setConfig((current) => (current ? { ...current, selectedGame: { appid: "", name: "Default" } } : current));
            return;
        }
        const saved = games.find((candidate) => candidate.appid === id);
        setConfig((current) => (current ? { ...current, selectedGame: saved || null } : current));
    };
    // Default target: FEX/audio/env edit tweaks.global; fan + scheduler are the LIVE system
    // modes, applied immediately through the backend.
    const applyMode = async (setter, mode) => {
        try {
            const next = await setter(mode);
            setConfig((current) => (current ? { ...current, fanMode: next.fanMode, lavdMode: next.lavdMode } : current));
        }
        catch (error) {
            reload();
        }
    };
    const presets = config.fexProfiles || {};
    const storedProfile = values.fexProfile;
    const fexValue = storedProfile && presets[storedProfile] ? storedProfile : "default";
    const fexOptions = Object.entries(presets).map(([id, profile]) => ({ data: id, label: profile.label }));
    const storedLatency = String(values.audioLatency ?? "");
    const audioValue = audioLatencyOptions.some((option) => option.data === storedLatency) ? storedLatency : "";
    const showFields = editingDefault || perGameEnabled;
    const has = hw(config);
    const showPerf = showFields && (has.fan || has.scheduler);
    return (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsxs(DFL.PanelSection, { title: t("PERFORMANCE & GAME TWEAKS"), children: [SP_JSX.jsx(SelectEdit, { label: t("Game"), value: game?.appid || "", options: targetOptions, onChange: setSelectedGame }), !editingDefault ? SP_JSX.jsx(DFL.ToggleField, { label: t("Use Per-Game Settings"), checked: perGameEnabled, onChange: setPerGameEnabled }) : null] }), !editingDefault ? SP_JSX.jsx(Suggestion, { config: config, appid: game.appid, apply: applySuggestion }) : null, showPerf ? (SP_JSX.jsx(DFL.PanelSection, { title: t("PERFORMANCE"), children: editingDefault ? (SP_JSX.jsxs(SP_JSX.Fragment, { children: [has.scheduler ? SP_JSX.jsx(SelectEdit, { label: t("CPU Scheduler"), value: config.lavdMode, options: lavdOptions, onChange: (mode) => applyMode(setLavdMode, mode) }) : null, has.fan ? SP_JSX.jsx(SelectEdit, { label: t("Fan Curve"), value: config.fanMode, options: fanOptions, onChange: (mode) => applyMode(setFanMode, mode) }) : null] })) : (SP_JSX.jsx(PerfFields, { config: config, values: values, patch: patchSettings })) })) : null, showFields ? (SP_JSX.jsxs(DFL.PanelSection, { title: t("GAME TWEAKS"), children: [SP_JSX.jsx("div", { className: "steamling-note", children: t("Changes apply on next game launch") }), editingDefault ? (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx(SelectEdit, { label: t("FEX Preset"), value: fexValue, options: fexOptions, onChange: (id) => patchSettings({ fexProfile: id }) }), SP_JSX.jsx(SelectEdit, { label: t("Audio Buffer"), value: audioValue, options: audioLatencyOptions, onChange: (id) => patchSettings({ audioLatency: id }) }), SP_JSX.jsx(XaliaToggle, { values: values, patch: patchSettings }), has.touchscreen ? SP_JSX.jsx(TouchField, { values: values, patch: patchSettings }) : null, SP_JSX.jsx(EnvVarsButton, { value: String(values.envVars ?? ""), onSave: (next) => patchSettings({ envVars: next }) })] })) : (SP_JSX.jsx(TweakFields, { config: config, appid: game.appid, values: values, patch: patchSettings }))] })) : null, !editingDefault && perGameEnabled ? (SP_JSX.jsx(ConfigSection, { game: { appid: game.appid, name: game.name || "" }, reload: reload })) : null, !editingDefault ? (SP_JSX.jsx(ShaderCache, { appid: game.appid, name: game.name || "", running: runtimeGame?.appid === game.appid })) : null] }));
}

// Replaces the stock "Add a Non-Steam Game" flow: Steam's file browser cannot open a new
// window under the Plasma Mobile X11 session, so Decky's in-UI picker feeds this instead.
const WINDOWS_EXE = /\.(exe|bat|msi)$/i;
// Constant internal name from proton-cachyos' compatibilitytool.vdf; survives version bumps.
const PROTON_TOOL = "proton-cachyos";
function isWindowsExe(path) {
    return WINDOWS_EXE.test(path);
}
function defaultShortcutName(path) {
    const base = path.split("/").pop() || path;
    const cleaned = base.replace(/\.[^.]+$/, "").replace(/_+/g, " ").trim();
    return cleaned || base;
}
const quote = (value) => `"${value.replace(/"/g, '\\"')}"`;
async function addShortcut(name, path, useProton) {
    const apps = window.SteamClient?.Apps;
    if (!apps?.AddShortcut)
        throw new Error("Steam shortcut API unavailable");
    const dir = path.slice(0, path.lastIndexOf("/") + 1) || "/";
    const appId = await apps.AddShortcut(name, path, "", "");
    if (typeof appId !== "number" || !appId)
        throw new Error("Steam refused to create the shortcut");
    apps.SetShortcutName?.(appId, name);
    apps.SetShortcutExe?.(appId, quote(path));
    apps.SetShortcutStartDir?.(appId, quote(dir));
    if (useProton)
        apps.SpecifyCompatTool?.(appId, PROTON_TOOL);
    ensureLaunchWrapper(String(appId >>> 0));
    return appId;
}

function AddGameModal({ path, closeModal }) {
    const [name, setName] = SP_REACT.useState(defaultShortcutName(path));
    const [proton, setProton] = SP_REACT.useState(isWindowsExe(path));
    const [busy, setBusy] = SP_REACT.useState(false);
    const submit = async () => {
        if (busy || !name.trim())
            return;
        setBusy(true);
        try {
            await addShortcut(name.trim(), path, proton);
            toaster.toast({ title: t("Added to library"), body: name.trim() });
            closeModal?.();
        }
        catch (error) {
            toaster.toast({ title: t("Could not add game"), body: String(error) });
            setBusy(false);
        }
    };
    return (SP_JSX.jsxs(DFL.ConfirmModal, { strTitle: t("Add Non-Steam Game"), strDescription: path, strOKButtonText: busy ? "Adding…" : "Add to Library", bOKDisabled: busy || !name.trim(), onCancel: () => closeModal?.(), onOK: submit, children: [SP_JSX.jsx(DFL.TextField, { label: t("Name"), value: name, disabled: busy, onChange: (event) => setName(event.target.value) }), SP_JSX.jsx(DFL.ToggleField, { label: t("Launch with Proton"), description: t("Needed for Windows games (.exe)"), checked: proton, disabled: busy, onChange: setProton })] }));
}
function AddGameSection() {
    const pick = async () => {
        try {
            // 0 = FileSelectionType.FILE (const enum in @decky/api typings, no runtime export).
            const result = await openFilePicker(0, "/home/deck", true, true);
            if (result?.path)
                DFL.showModal(SP_JSX.jsx(AddGameModal, { path: result.path }));
        }
        catch (error) {
            // Picker closed without a selection.
        }
    };
    return (SP_JSX.jsxs(DFL.PanelSection, { title: t("LIBRARY"), children: [SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", onClick: pick, children: t("Add Non-Steam Game") }) }), SP_JSX.jsx("div", { className: "steamling-note", children: t("Pick an executable to add it to your Steam library") })] }));
}

// The share is guest-writable and covers the whole home folder, so the trade is spelled out
// rather than buried: same warning the Steamling Tools menu shows before it flips the switch.
function ShareConfirmModal({ onConfirm, closeModal }) {
    const [running, setRunning] = SP_REACT.useState(false);
    const runningRef = SP_REACT.useRef(false);
    runningRef.current = running;
    const start = async () => {
        if (runningRef.current)
            return;
        setRunning(true);
        await onConfirm();
        closeModal?.();
    };
    return (SP_JSX.jsx(DFL.ConfirmModal, { strTitle: t("Share Files Over The Network"), strDescription: running
            ? "Starting…"
            : "Anyone on the same network can read and write every file in your home folder - games, saves and emulator settings, but also your Steam login and SSH keys. There is no password. Only turn this on at home.", strOKButtonText: running ? "Starting…" : "Turn On Sharing", bDestructiveWarning: true, bOKDisabled: running, bCancelDisabled: running, bDisableBackgroundDismiss: true, onCancel: () => {
            if (!runningRef.current)
                closeModal?.();
        }, onOK: start }));
}
function FileSharing() {
    const [share, setShareState] = SP_REACT.useState(null);
    const [busy, setBusy] = SP_REACT.useState(false);
    const [status, setStatus] = SP_REACT.useState("");
    const busyRef = SP_REACT.useRef(false);
    busyRef.current = busy;
    const visible = useQamVisible();
    // Polled only while the menu is open; reopening refreshes at once.
    SP_REACT.useEffect(() => {
        if (!visible)
            return;
        let cancelled = false;
        const refresh = async () => {
            if (busyRef.current)
                return;
            try {
                const next = await shareStatus();
                if (!cancelled && !busyRef.current)
                    setShareState(next);
            }
            catch (error) {
                if (!cancelled)
                    setStatus(String(error));
            }
        };
        refresh();
        const timer = window.setInterval(refresh, 5000);
        return () => {
            cancelled = true;
            window.clearInterval(timer);
        };
    }, [visible]);
    const run = async (action) => {
        if (busyRef.current)
            return;
        setBusy(true);
        setStatus("");
        try {
            setShareState(await action());
        }
        catch (error) {
            setStatus(String(error));
        }
        finally {
            setBusy(false);
        }
    };
    const summary = () => {
        if (status)
            return status;
        if (!share)
            return "Checking…";
        if (!share.installed)
            return "Samba is not installed (7.4 MB download)";
        if (share.on)
            return "On - open smb://steamling.local and connect as Guest";
        return "Off - your home folder is not shared";
    };
    return (SP_JSX.jsxs(DFL.PanelSection, { title: t("FILE SHARING"), children: [SP_JSX.jsx(DFL.Field, { label: t("Network share"), description: summary() }), share && !share.installed ? (SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", disabled: busy, onClick: () => run(installSamba), children: busy ? "Installing…" : "Install Samba" }) })) : (SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ToggleField, { label: t("Share my home folder"), description: t("Drag files straight onto the device from another computer"), checked: !!share?.on, disabled: busy || !share?.installed, onChange: (on) => {
                        if (busyRef.current)
                            return;
                        if (on)
                            DFL.showModal(SP_JSX.jsx(ShareConfirmModal, { onConfirm: () => run(() => setShare(true)) }));
                        else
                            run(() => setShare(false));
                    } }) }))] }));
}

// Same warning the Steamling Tools menu shows: every image ships the same default password.
function SshConfirmModal({ onConfirm, closeModal }) {
    const [running, setRunning] = SP_REACT.useState(false);
    const runningRef = SP_REACT.useRef(false);
    runningRef.current = running;
    const start = async () => {
        if (runningRef.current)
            return;
        setRunning(true);
        await onConfirm();
        closeModal?.();
    };
    return (SP_JSX.jsx(DFL.ConfirmModal, { strTitle: t("Allow SSH Logins"), strDescription: running
            ? "Starting…"
            : "Anyone on the same network can then log in with an account password, and Steamling ships a well-known default one. If you have not changed it yet, do that first: open Konsole in desktop mode and run passwd. It stays on, across reboots, until you turn it off here.", strOKButtonText: running ? "Starting…" : "Turn On SSH", bDestructiveWarning: true, bOKDisabled: running, bCancelDisabled: running, bDisableBackgroundDismiss: true, onCancel: () => {
            if (!runningRef.current)
                closeModal?.();
        }, onOK: start }));
}
function RemoteAccess() {
    const [ssh, setSshState] = SP_REACT.useState(null);
    const [busy, setBusy] = SP_REACT.useState(false);
    const [status, setStatus] = SP_REACT.useState("");
    const busyRef = SP_REACT.useRef(false);
    busyRef.current = busy;
    const visible = useQamVisible();
    // Read once per open: nothing else flips it while the menu is up, and each read is a transient unit.
    SP_REACT.useEffect(() => {
        if (!visible)
            return;
        let cancelled = false;
        sshStatus()
            .then((next) => {
            if (!cancelled && !busyRef.current)
                setSshState(next);
        })
            .catch((error) => {
            if (!cancelled)
                setStatus(String(error));
        });
        return () => {
            cancelled = true;
        };
    }, [visible]);
    const run = async (on) => {
        if (busyRef.current)
            return;
        setBusy(true);
        setStatus("");
        try {
            setSshState(await setSsh(on));
        }
        catch (error) {
            setStatus(String(error));
        }
        finally {
            setBusy(false);
        }
    };
    if (ssh && !ssh.available)
        return null;
    const summary = () => {
        if (status)
            return status;
        if (!ssh)
            return "Checking…";
        if (!ssh.on)
            return "Off - the device does not accept SSH logins";
        if (ssh.addresses.length === 0)
            return "On - connect to Wi-Fi to reach it";
        return `On - ${ssh.addresses.map((a) => `ssh deck@${a}`).join(" or ")}`;
    };
    return (SP_JSX.jsxs(DFL.PanelSection, { title: t("REMOTE ACCESS"), children: [SP_JSX.jsx(DFL.Field, { label: t("SSH"), description: summary() }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ToggleField, { label: t("Allow SSH logins"), description: t("Log in from another computer's terminal"), checked: !!ssh?.on, disabled: busy || !ssh, onChange: (on) => {
                        if (busyRef.current)
                            return;
                        if (on)
                            DFL.showModal(SP_JSX.jsx(SshConfirmModal, { onConfirm: () => run(true) }));
                        else
                            run(false);
                    } }) })] }));
}

function cardSummary(card) {
    if (!card)
        return "Checking…";
    if (!card.present)
        return "No SD card detected";
    if (card.bootDisk)
        return "Booted from this card - formatting disabled";
    const size = card.sizeBytes ? `${(card.sizeBytes / 1e9).toFixed(1)} GB` : "";
    const state = card.fstype === "ext4" ? (card.mountpoint ? "mounted" : "") : "not formatted for Steam";
    return [card.label || "unlabeled", size, card.fstype || "no filesystem", state].filter(Boolean).join(" · ");
}
// closeModal must not be forwarded to ConfirmModal: its OK handler would close the dialog
// at once, and it has to stay open until the format finishes.
function FormatConfirmModal({ summary, onConfirm, closeModal }) {
    const [text, setText] = SP_REACT.useState("");
    const [running, setRunning] = SP_REACT.useState(false);
    const armedRef = SP_REACT.useRef(false);
    const runningRef = SP_REACT.useRef(false);
    armedRef.current = text.trim().toLowerCase() === "format";
    runningRef.current = running;
    const start = async () => {
        if (!armedRef.current || runningRef.current)
            return;
        setRunning(true);
        await onConfirm();
        closeModal?.();
    };
    return (SP_JSX.jsx(DFL.ConfirmModal, { strTitle: t("Format SD Card"), strDescription: running
            ? "Formatting… This can take a minute. Do not remove the card."
            : `This erases ALL data on the card (${summary}) and formats it for Steam. Type "format" and press Enter to confirm.`, strOKButtonText: running ? "Formatting…" : "Erase and Format", bDestructiveWarning: true, bOKDisabled: !armedRef.current || running, bCancelDisabled: running, bDisableBackgroundDismiss: true, bHideCloseIcon: true, onCancel: () => {
            if (!runningRef.current)
                closeModal?.();
        }, onOK: start, children: !running ? (SP_JSX.jsx(DFL.TextField, { value: text, focusOnMount: true, onChange: (event) => setText(event.target.value), onKeyDown: (event) => {
                if (event.key === "Enter")
                    start();
            } })) : null }));
}
function SdCard() {
    const [card, setCard] = SP_REACT.useState(null);
    const [label, setLabel] = SP_REACT.useState("SDCARD");
    const [busy, setBusy] = SP_REACT.useState(false);
    const [status, setStatus] = SP_REACT.useState("");
    const busyRef = SP_REACT.useRef(false);
    busyRef.current = busy;
    const visible = useQamVisible();
    // Polled only while the menu is open; reopening refreshes at once.
    SP_REACT.useEffect(() => {
        if (!visible)
            return;
        let cancelled = false;
        const refresh = async () => {
            if (busyRef.current)
                return;
            try {
                const next = await detectSdcard();
                if (!cancelled && !busyRef.current)
                    setCard(next);
            }
            catch (error) {
                if (!cancelled)
                    setStatus(String(error));
            }
        };
        refresh();
        const timer = window.setInterval(refresh, 5000);
        return () => {
            cancelled = true;
            window.clearInterval(timer);
        };
    }, [visible]);
    const runFormat = async () => {
        if (busyRef.current)
            return;
        setBusy(true);
        setStatus("");
        try {
            const next = await formatSdcard(label);
            setCard(next);
        }
        catch (error) {
            setStatus(String(error));
        }
        finally {
            setBusy(false);
        }
    };
    const confirmFormat = () => DFL.showModal(SP_JSX.jsx(FormatConfirmModal, { summary: cardSummary(card), onConfirm: runFormat }));
    return (SP_JSX.jsxs(DFL.PanelSection, { title: t("SD CARD"), children: [SP_JSX.jsx(DFL.Field, { label: t("Card"), description: cardSummary(card) }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.TextField, { label: t("Label"), value: label, disabled: busy || !!card?.bootDisk, onChange: (event) => setLabel(event.target.value.replace(/[^A-Za-z0-9_-]/g, "").slice(0, 16)) }) }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", disabled: !card?.present || busy || !!card?.bootDisk, onClick: confirmFormat, children: busy ? "Formatting…" : "Format SD Card" }) }), status ? SP_JSX.jsx(DFL.Field, { label: "", description: status }) : null] }));
}

function UsbTransfer() {
    const [usb, setUsb] = SP_REACT.useState(null);
    const [busy, setBusy] = SP_REACT.useState(false);
    const [status, setStatus] = SP_REACT.useState("");
    const busyRef = SP_REACT.useRef(false);
    busyRef.current = busy;
    const visible = useQamVisible();
    SP_REACT.useEffect(() => {
        if (!visible)
            return;
        let cancelled = false;
        usbTransferStatus()
            .then((next) => {
            if (!cancelled && !busyRef.current)
                setUsb(next);
        })
            .catch((error) => {
            if (!cancelled)
                setStatus(String(error));
        });
        return () => {
            cancelled = true;
        };
    }, [visible]);
    const run = async (on) => {
        if (busyRef.current)
            return;
        setBusy(true);
        setStatus("");
        try {
            setUsb(await setUsbTransfer(on));
        }
        catch (error) {
            setStatus(String(error));
        }
        finally {
            setBusy(false);
        }
    };
    if (usb && !usb.available)
        return null;
    const summary = () => {
        if (status)
            return status;
        if (!usb)
            return "Checking…";
        if (usb.on)
            return "On - plug into a computer with a USB-C cable and open \"Steamling\" like a phone. Controllers and hubs on the port stop working until you turn this off.";
        return "Off";
    };
    return (SP_JSX.jsxs(DFL.PanelSection, { title: t("USB FILE TRANSFER"), children: [SP_JSX.jsx(DFL.Field, { label: t("Transfer over USB"), description: summary() }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ToggleField, { label: t("Show up on a computer"), description: t("Copy files over a cable, no network needed. Stays on until you restart."), checked: !!usb?.on, disabled: busy || !usb, onChange: (on) => run(on) }) })] }));
}

// SD card last: the only destructive action, kept away from the casual toggles
function Library() {
    return (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx(AddGameSection, {}), SP_JSX.jsx(FileSharing, {}), SP_JSX.jsx(UsbTransfer, {}), SP_JSX.jsx(RemoteAccess, {}), SP_JSX.jsx(SdCard, {})] }));
}

function About() {
    const [info, setInfo] = SP_REACT.useState(null);
    const [error, setError] = SP_REACT.useState("");
    const visible = useQamVisible();
    // Once per open: the bootloader check reads both ABL slots, so it is not polled.
    SP_REACT.useEffect(() => {
        if (!visible)
            return;
        let cancelled = false;
        deviceInfo()
            .then((next) => {
            if (!cancelled)
                setInfo(next);
        })
            .catch((err) => {
            if (!cancelled)
                setError(String(err));
        });
        return () => {
            cancelled = true;
        };
    }, [visible]);
    const confirmRestart = () => DFL.showModal(SP_JSX.jsx(DFL.ConfirmModal, { strTitle: t("Restart Game Mode"), strDescription: t("Closes Steam and any running game, then brings game mode back up. Unsaved progress in a running game is lost. Useful when Steam or the screen gets stuck."), strOKButtonText: t("Restart"), onOK: () => restartGameMode().catch((err) => setError(String(err))) }));
    return (SP_JSX.jsxs(DFL.PanelSection, { title: t("ABOUT"), children: [SP_JSX.jsx(DFL.Field, { label: t("Steamling OS"), description: info?.osVersion ?? "…" }), SP_JSX.jsx(DFL.Field, { label: t("Kernel"), description: info?.kernel ?? "…" }), info?.bootloader ? SP_JSX.jsx(DFL.Field, { label: t("Bootloader"), description: info.bootloader }) : null, SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", onClick: confirmRestart, children: t("Restart Game Mode") }) }), error ? SP_JSX.jsx(DFL.Field, { label: t("Error"), description: error }) : null] }));
}

const SHOWN_UPDATES = 8;
const gib = (bytes) => (bytes / 1024 ** 3).toFixed(1);
// snapshot metadata stores ISO-8601 UTC; show local DD/MM/YYYY HH:MM
const fmtDate = (iso) => {
    const d = new Date(iso);
    if (isNaN(d.getTime()))
        return iso;
    const p = (n) => String(n).padStart(2, "0");
    return `${p(d.getDate())}-${p(d.getMonth() + 1)}-${d.getFullYear()} ${p(d.getHours())}:${p(d.getMinutes())}`;
};
function Updater() {
    const [updates, setUpdates] = SP_REACT.useState(null);
    const [checking, setChecking] = SP_REACT.useState(false);
    const [status, setStatus] = SP_REACT.useState(null);
    const [snap, setSnap] = SP_REACT.useState(null);
    const [rollingBack, setRollingBack] = SP_REACT.useState(false);
    const [rollbackDone, setRollbackDone] = SP_REACT.useState(false);
    const [error, setError] = SP_REACT.useState("");
    const [rollbackError, setRollbackError] = SP_REACT.useState("");
    const busyRef = SP_REACT.useRef(false);
    const running = !!status?.running;
    busyRef.current = checking || running || rollingBack;
    const visible = useQamVisible();
    const refreshSnap = () => snapshotStatus().then(setSnap).catch(() => { });
    // Re-attach to an update that survived a QAM close (or a Steam restart), on every open.
    SP_REACT.useEffect(() => {
        if (!visible)
            return;
        let cancelled = false;
        updateStatus()
            .then((next) => {
            if (!cancelled && (next.running || next.exitCode !== null))
                setStatus(next);
        })
            .catch(() => { });
        refreshSnap();
        return () => {
            cancelled = true;
        };
    }, [visible]);
    // The update itself runs on regardless; only the progress display stops while hidden.
    SP_REACT.useEffect(() => {
        if (!running || !visible)
            return;
        const timer = window.setInterval(async () => {
            try {
                const next = await updateStatus();
                setStatus(next);
                if (!next.running) {
                    if (next.exitCode === 0)
                        setUpdates([]);
                    refreshSnap(); // a finished transaction changes snapshots + reboot-required
                }
            }
            catch (err) {
                setError(String(err));
            }
        }, 2000);
        return () => window.clearInterval(timer);
    }, [running, visible]);
    const check = async () => {
        if (busyRef.current)
            return;
        setChecking(true);
        setError("");
        try {
            setUpdates(await checkUpdates());
        }
        catch (err) {
            setError(String(err));
        }
        finally {
            setChecking(false);
        }
    };
    const start = async () => {
        if (busyRef.current)
            return;
        setError("");
        try {
            setStatus(await startUpdate());
        }
        catch (err) {
            setError(String(err));
        }
    };
    const confirmStart = () => DFL.showModal(SP_JSX.jsx(DFL.ConfirmModal, { strTitle: t("Install Updates"), strDescription: t("Downloads and installs all available system updates. Keep the device powered; a running game may stutter. Restart after it finishes."), strOKButtonText: t("Install"), onOK: start }));
    const lastSnapshot = snap?.supported && snap.snapshots.length > 0 ? snap.snapshots[snap.snapshots.length - 1] : null;
    // Already rolled back onto the latest snapshot: another rollback would be a no-op,
    // so hide the button until the next update (which clears the marker + snapshots anew).
    const onLastSnapshot = !!(snap?.rolledBack && lastSnapshot && snap.rolledBack.fromSnapshot === lastSnapshot.id);
    const rollBack = async () => {
        if (busyRef.current || !lastSnapshot)
            return;
        setRollbackError("");
        setRollingBack(true);
        try {
            setSnap(await startRollback(lastSnapshot.id));
            setRollbackDone(true);
        }
        catch (err) {
            setRollbackError(String(err));
        }
        finally {
            setRollingBack(false);
        }
    };
    const confirmRollback = () => {
        if (!lastSnapshot)
            return;
        DFL.showModal(SP_JSX.jsx(DFL.ConfirmModal, { strTitle: t("Roll Back Last Update"), strDescription: `Restores the system to before the update of ${fmtDate(lastSnapshot.created)}` +
                (lastSnapshot.targets ? ` (${lastSnapshot.targets})` : "") +
                `. Games, saves and settings are kept.` +
                (lastSnapshot.kernel ? " The previous kernel is restored too." : "") +
                ` Reboot after it completes.`, strOKButtonText: t("Roll Back"), onOK: rollBack }));
    };
    const reboot = () => rebootSystem().catch((err) => setError(String(err)));
    const finished = !running && status?.exitCode !== null && status?.exitCode !== undefined;
    const summary = updates === null
        ? "Not checked yet"
        : updates.length === 0
            ? "System is up to date"
            : `${updates.length} update${updates.length === 1 ? "" : "s"} available`;
    return (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsxs(DFL.PanelSection, { title: t("SYSTEM UPDATES"), children: [!running ? SP_JSX.jsx(DFL.Field, { label: t("Status"), description: summary }) : null, !running && updates && updates.length > 0 ? (SP_JSX.jsxs("div", { className: "steamling-note", children: [updates.slice(0, SHOWN_UPDATES).map((update) => (SP_JSX.jsx("div", { children: `${update.name} ${update.current} → ${update.latest}` }, update.name))), updates.length > SHOWN_UPDATES ? SP_JSX.jsx("div", { children: `… and ${updates.length - SHOWN_UPDATES} more` }) : null] })) : null, SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", disabled: busyRef.current, onClick: check, children: checking ? "Checking…" : "Check for Updates" }) }), !running && updates && updates.length > 0 ? (SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", disabled: busyRef.current, onClick: confirmStart, children: t("Install Updates") }) })) : null, running ? SP_JSX.jsx(DFL.Field, { label: t("Updating…"), description: t("Safe to close this menu. Do not power off.") }) : null, finished ? (SP_JSX.jsx(DFL.Field, { label: status.exitCode === 0 ? "Update complete" : `Update failed (code ${status.exitCode})`, description: status.exitCode === 0 ? "Restart to finish applying updates." : "See the log below." })) : null, finished && status.exitCode === 0 ? (SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", onClick: reboot, children: t("Restart Now") }) })) : null, (running || (finished && status.exitCode !== 0)) && status?.log ? (SP_JSX.jsx("div", { className: "steamling-note steamling-log", children: status.log })) : null, error ? SP_JSX.jsx(DFL.Field, { label: t("Error"), description: error }) : null] }), snap?.supported ? (SP_JSX.jsxs(DFL.PanelSection, { title: t("ROLLBACK"), children: [snap.rolledBack && !rollbackDone ? (SP_JSX.jsx(DFL.Field, { label: t("System was rolled back"), description: `Restored from snapshot ${snap.rolledBack.fromSnapshot} (${fmtDate(snap.rolledBack.ts)}).${onLastSnapshot ? " Rollback will be available again after the next update." : ""}` })) : null, rollbackDone ? (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx(DFL.Field, { label: t("Rolled back"), description: t("Reboot to finish switching to the restored system.") }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", onClick: reboot, children: t("Reboot Now") }) })] })) : onLastSnapshot ? null : lastSnapshot ? (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx(DFL.Field, { label: t("Last snapshot"), description: `${fmtDate(lastSnapshot.created)}${lastSnapshot.targets ? ` — ${lastSnapshot.targets}` : ""}` }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", disabled: busyRef.current, onClick: confirmRollback, children: rollingBack ? "Rolling back…" : "Roll Back Last Update" }) })] })) : (SP_JSX.jsx(DFL.Field, { label: t("No snapshots yet"), description: t("A snapshot is taken automatically before every update.") })), rollbackError ? SP_JSX.jsx(DFL.Field, { label: t("Rollback error"), description: rollbackError }) : null, SP_JSX.jsx(DFL.Field, { label: t("Storage"), description: `${gib(snap.freeBytes)} GB free${snap.lowSpace ? " — LOW: snapshots may be skipped" : ""}` })] })) : null, SP_JSX.jsx(About, {})] }));
}

// A loader whose API lacks the hook gets the old behaviour (always treated as open) instead of
// a crash; the choice is fixed per load, so hook order stays stable.
const useVisible = typeof useQuickAccessVisible === "function" ? useQuickAccessVisible : () => true;
function Content() {
    const [tab, setTab] = SP_REACT.useState("Games");
    const [config, setConfig] = SP_REACT.useState(null);
    const [message, setMessage] = SP_REACT.useState("Loading");
    const savedTweaksSnapshot = SP_REACT.useRef("");
    const visible = useVisible();
    const configRef = SP_REACT.useRef(config);
    configRef.current = config;
    const load = SP_REACT.useCallback(async () => {
        try {
            const next = await getConfig();
            next.game = currentGame();
            next.selectedGame = next.game || null;
            savedTweaksSnapshot.current = JSON.stringify(next.tweaks);
            setConfig(next);
        }
        catch (error) {
            setMessage(String(error));
        }
    }, []);
    SP_REACT.useEffect(() => {
        load();
    }, [load]);
    // Mounted once for the whole session, so re-read on every open: games installed since, and
    // edits saved from a library context-menu modal, which this copy would otherwise overwrite
    // on its next save. Skipped while an edit of our own is still waiting to be saved.
    const wasVisible = SP_REACT.useRef(visible);
    SP_REACT.useEffect(() => {
        const opened = visible && !wasVisible.current;
        wasVisible.current = visible;
        if (!opened)
            return;
        const current = configRef.current;
        if (current && JSON.stringify(current.tweaks) !== savedTweaksSnapshot.current)
            return;
        load();
    }, [visible, load]);
    // Track the running game so opening the QAM mid-game edits that game's profile: read on every
    // open, then on Steam's own start/stop notifications rather than by polling. The router may
    // update a moment after the notification, hence the short delay.
    SP_REACT.useEffect(() => {
        if (!config || !visible)
            return;
        let cancelled = false;
        const refreshRuntime = () => {
            try {
                const runtimeGame = currentGame();
                if (cancelled)
                    return;
                setConfig((current) => {
                    if (!current)
                        return current;
                    if ((current.game?.appid || "") === (runtimeGame?.appid || "") && (current.game?.name || "") === (runtimeGame?.name || ""))
                        return current;
                    return { ...current, game: runtimeGame };
                });
            }
            catch (error) {
            }
        };
        let timer;
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
    if (!config)
        return SP_JSX.jsx(DFL.PanelSection, { title: "Governor", children: SP_JSX.jsx(DFL.Field, { label: message }) });
    const tabContent = (content) => (SP_JSX.jsx("div", { className: "steamling-control-tab-content", children: content }));
    const tabs = [
        { id: "Games", title: tabIcons.Games, content: tabContent(SP_JSX.jsx(Games, { config: config, setConfig: setConfig, reload: load })) },
        { id: "Display", title: tabIcons.Display, content: tabContent(SP_JSX.jsx(Display, {})) },
        { id: "Library", title: tabIcons.Library, content: tabContent(SP_JSX.jsx(Library, {})) },
        { id: "Controller", title: tabIcons.Controller, content: tabContent(SP_JSX.jsx(Controller, { config: config, setConfig: setConfig, reload: load })) },
        { id: "Updater", title: tabIcons.Updater, content: tabContent(SP_JSX.jsx(Updater, {})) },
    ];
    return (SP_JSX.jsx(QamVisible.Provider, { value: visible, children: SP_JSX.jsxs("div", { className: "steamling-control-tabs", children: [SP_JSX.jsx("style", { children: styles }), SP_JSX.jsx(MenuWidthStyle, {}), SP_JSX.jsx(DFL.Tabs, { activeTab: tab, onShowTab: setTab, tabs: tabs })] }) }));
}

/** Standalone per-game settings, opened from the library context menu. Saves on each change
 *  (no QAM debounce lifecycle here; the modal has an explicit close). */
function GameSettingsModal({ appid, name, closeModal }) {
    const [config, setConfig] = SP_REACT.useState(null);
    SP_REACT.useEffect(() => {
        getConfig()
            .then(setConfig)
            .catch(() => closeModal?.());
    }, []);
    if (!config)
        return SP_JSX.jsx(DFL.ModalRoot, { closeModal: closeModal, children: t("Loading…") });
    const gameSettings = config.tweaks.games[appid] || {};
    const enabled = gameSettings.enabled === true;
    const values = enabled ? { ...config.tweaks.global, ...gameSettings } : config.tweaks.global;
    const update = (mutate) => {
        const next = clone(config);
        mutate(next);
        setConfig(next);
        saveTweaks(next.tweaks).catch(() => { });
    };
    const patch = (fields) => update((next) => {
        const existing = next.tweaks.games[appid] || {};
        next.tweaks.games[appid] = { ...existing, enabled: true, name, ...fields };
    });
    return (SP_JSX.jsxs(DFL.ModalRoot, { closeModal: closeModal, children: [SP_JSX.jsx("div", { style: { fontWeight: 600, marginBottom: "8px" }, children: name || `App ${appid}` }), SP_JSX.jsx(DFL.ToggleField, { label: t("Use Per-Game Settings"), checked: enabled, onChange: (on) => {
                    update((next) => {
                        next.tweaks.games[appid] = { ...(next.tweaks.games[appid] || {}), enabled: on, name };
                    });
                } }), enabled ? (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx(PerfFields, { config: config, values: values, patch: patch }), SP_JSX.jsx(TweakFields, { config: config, appid: appid, values: values, patch: patch }), SP_JSX.jsx(ConfigSection, { game: { appid, name }, reload: () => getConfig().then(setConfig).catch(() => { }) })] })) : null] }));
}

// LibraryContextMenu is not a module export, so it is reached by classname marker ->
// `navigator:` wrapper -> fake-render, whose element type is the real class.
// Steam UI internals are unversioned: every step is guarded so a shape change costs the
// menu item, never the plugin.
function patchLibraryContextMenu() {
    try {
        const menuModule = DFL.findModuleChild((mod) => {
            if (typeof mod !== "object" || !mod)
                return undefined;
            for (const prop in mod) {
                try {
                    if (mod[prop]?.toString?.()?.includes("().LibraryContextMenu"))
                        return mod;
                }
                catch (error) { }
            }
            return undefined;
        });
        if (!menuModule)
            return () => { };
        const wrapper = Object.values(menuModule).find((member) => {
            try {
                return typeof member === "function" && member?.toString?.()?.includes("navigator:");
            }
            catch (error) {
                return false;
            }
        });
        if (!wrapper)
            return () => { };
        const LibraryContextMenu = DFL.fakeRenderComponent(wrapper)?.type;
        if (!LibraryContextMenu?.prototype?.BuildManageSubmenu)
            return () => { };
        // The builder returns either a plain item array or an element with children.
        const patch = DFL.afterPatch(LibraryContextMenu.prototype, "BuildManageSubmenu", function (_args, ret) {
            try {
                const overview = this.props?.overview;
                const appid = overview?.appid;
                if (!appid)
                    return ret;
                const children = Array.isArray(ret) ? ret : ret?.props?.children;
                if (!Array.isArray(children))
                    return ret;
                if (children.some((child) => child?.key === "steamling-settings"))
                    return ret;
                children.push(SP_JSX.jsx(DFL.MenuItem, { onSelected: () => DFL.showModal(SP_JSX.jsx(GameSettingsModal, { appid: String(appid), name: String(overview?.display_name ?? "") })), children: "Governor Settings" }, "steamling-settings"));
            }
            catch (error) { }
            return ret;
        });
        return () => patch.unpatch();
    }
    catch (error) {
        return () => { };
    }
}

var index = definePlugin(() => {
    const unpatchContextMenu = patchLibraryContextMenu();
    const unregisterTouch = registerTouchLifetime();
    const unregisterDownloads = registerDownloadWrapper((appid) => isGame(appid));
    // Wider from the first time the menu opens, not only once this plugin's page has been shown.
    applyToSteamWindow(getMenuWidth());
    getConfig()
        .then((config) => wrapAllGames(installedSteamGames(config)))
        .then(() => wrapShortcuts(nonSteamShortcuts().map((shortcut) => shortcut.appid)))
        .catch(() => { });
    return {
        name: "Governor",
        content: SP_JSX.jsx(Content, {}),
        icon: pluginIcon,
        alwaysRender: true,
        onDismount() {
            unpatchContextMenu();
            unregisterTouch();
            unregisterDownloads();
            applyToSteamWindow(null);
        },
    };
});

export { index as default };
//# sourceMappingURL=index.js.map
