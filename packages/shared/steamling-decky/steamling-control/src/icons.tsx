import type { ReactNode } from "react";

function Icon({ path }: { path: ReactNode }) {
  return (
    <svg
      style={{ display: "block" }}
      width="20"
      height="20"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      {path}
    </svg>
  );
}

export const tabIcons = {
  // This Game: a game cartridge, for one game's settings and tweaks.
  ThisGame: (
    <Icon
      path={
        <>
          <path d="M6 3h12a1 1 0 0 1 1 1v15a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V4a1 1 0 0 1 1-1z" />
          <rect width="8" height="6" x="8" y="6" rx="1" />
          <path d="M9 17v1" />
          <path d="M12 17v1" />
          <path d="M15 17v1" />
        </>
      }
    />
  ),
  // Performance: a gauge with its needle swung toward high, for the overlay, CPU scheduler, fan
  // curve and system monitor that live under this tab.
  Performance: (
    <Icon
      path={
        <>
          <path d="M3.34 19a10 10 0 1 1 17.32 0" />
          <path d="M6 14h1.5" />
          <path d="M12 6.5V8" />
          <path d="M16.5 14H18" />
          <path d="m12 14 4.5-4.5" />
          <circle cx="12" cy="14" r="1.5" fill="currentColor" />
        </>
      }
    />
  ),
  // The gamepad: calibration, stick response, paddles and rumble all live under this tab.
  Controller: (
    <Icon
      path={
        <>
          <line x1="6" x2="10" y1="11" y2="11" />
          <line x1="8" x2="8" y1="9" y2="13" />
          <line x1="15" x2="15.01" y1="12" y2="12" />
          <line x1="18" x2="18.01" y1="10" y2="10" />
          <path d="M17.32 5H6.68a4 4 0 0 0-3.978 3.59c-.006.052-.01.101-.017.152C2.604 9.416 2 14.456 2 16a3 3 0 0 0 3 3c1 0 1.5-.5 2-1l1.414-1.414A2 2 0 0 1 9.828 16h4.344a2 2 0 0 1 1.414.586L17 18c.5.5 1 1 2 1a3 3 0 0 0 3-3c0-1.545-.604-6.584-.685-7.258-.007-.05-.011-.1-.017-.151A4 4 0 0 0 17.32 5z" />
        </>
      }
    />
  ),
  // Files: a folder, for adding games and moving files on and off the handheld.
  Files: (
    <Icon
      path={<path d="M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z" />}
    />
  ),
  // System: a gear, for updates, remote access, the set-once screen settings and versions.
  System: (
    <Icon
      path={
        <>
          <path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z" />
          <circle cx="12" cy="12" r="3" />
        </>
      }
    />
  ),
};

/** Governor's own icon: a flyball governor, the spinning regulator that holds a steam engine's speed.
 * Sized to fill the height of its row in Decky's plugin list; the view box is cropped to the
 * drawing, so none of that size goes on empty margin. */
export const pluginIcon = (
  <svg
    style={{ display: "block" }}
    width="1.75em"
    height="1.75em"
    viewBox="1.5 1 21 21"
    fill="none"
    stroke="currentColor"
    strokeWidth="2"
    strokeLinecap="round"
    strokeLinejoin="round"
  >
    <line x1="12" x2="12" y1="2" y2="21" />
    <path d="M12 4 7.6 9.4M12 4l4.4 5.4" />
    <circle cx="6.5" cy="11" r="1.9" fill="currentColor" />
    <circle cx="17.5" cy="11" r="1.9" fill="currentColor" />
    <path d="M7.6 12.6 10.5 15.5M16.4 12.6 13.5 15.5" />
    <rect x="10" y="15" width="4" height="2.5" rx="0.5" />
    <line x1="7" x2="17" y1="21" y2="21" />
  </svg>
);
