import { findClassModule, findSP, quickAccessMenuClasses } from "@decky/ui";

// Steam draws the quick access menu 348px wide: a 48px tab strip plus a 300px page. The menu is
// its own window, sized and placed from a placeholder in Steam's main window that is 854px wide
// and shifted right by 506px, so 348px of it is on screen. Making the placeholder wider (it is
// anchored to the right edge) brings more of the menu on screen without touching the slide-in
// transform. The friends list's expanded view resizes itself and is left alone.
const WIDTHS = { standard: 0, wide: 100, wider: 200 } as const;
export type MenuWidth = keyof typeof WIDTHS;

const KEY = "steamling-control.menu-width";
const DEFAULT: MenuWidth = "wide";
const listeners = new Set<(width: MenuWidth) => void>();

export function getMenuWidth(): MenuWidth {
  try {
    const saved = window.localStorage.getItem(KEY);
    if (saved && saved in WIDTHS) return saved as MenuWidth;
  } catch (error) {
  }
  return DEFAULT;
}

export function setMenuWidth(width: MenuWidth) {
  try {
    window.localStorage.setItem(KEY, width);
  } catch (error) {
  }
  for (const listener of listeners) listener(width);
}

export function onMenuWidth(listener: (width: MenuWidth) => void): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

type Classes = Record<string, string | undefined>;

// Steam's hashed class names, looked up by the names its own code uses. The placeholder lives in
// Steam's main window; the panel inside it is a separate window (the menu's own document).
const viewClasses = (findClassModule((m) => m.ViewPlaceholder && m.Expanded) || quickAccessMenuClasses) as Classes;
const panelClasses = (findClassModule((m) => m.TabGroupPanel && m.HeaderContainer && m.Footer) || quickAccessMenuClasses) as Classes;

function cls(map: Classes, key: string): string {
  return map?.[key] ? `.${map[key]!.split(" ")[0]}` : "";
}

/** For Steam's main window: the placeholder sets the size and position of the menu's window. */
function placeholderCss(width: MenuWidth): string {
  const extra = WIDTHS[width];
  const placeholder = cls(viewClasses, "ViewPlaceholder");
  if (!extra || !placeholder) return "";
  const expanded = cls(viewClasses, "Expanded");
  const open = expanded ? `${placeholder}:not(${expanded})` : placeholder;
  return `${open} { width: ${854 + extra}px !important; }`;
}

/** For the menu's own window: let the page, header and footer fill the extra room. */
export function panelCss(width: MenuWidth): string {
  const extra = WIDTHS[width];
  if (!extra) return "";
  const expanded = cls(viewClasses, "Expanded");
  const notExpanded = expanded ? `:not(${expanded} *)` : "";
  const rules: string[] = [];
  const panel = cls(panelClasses, "TabGroupPanel");
  const header = cls(panelClasses, "HeaderContainer");
  const footer = cls(panelClasses, "Footer");
  if (panel) rules.push(`${panel}:not(.tab_Friends) { max-width: ${300 + extra}px !important; }`);
  if (header) rules.push(`${header}${notExpanded} { max-width: ${348 + extra}px !important; }`);
  if (footer) rules.push(`${footer}${notExpanded} { width: ${348 + extra}px !important; }`);
  return rules.join("\n");
}

const STYLE_ID = "steamling-control-menu-width";

/** Puts the placeholder rule into Steam's main window, or takes it out again. */
export function applyToSteamWindow(width: MenuWidth | null) {
  let doc: Document | undefined;
  try {
    doc = findSP()?.document;
  } catch (error) {
  }
  if (!doc) return;
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
