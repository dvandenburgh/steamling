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
  // Performance: a gauge with its needle swung toward high, for the fan curve, CPU scheduler,
  // overlay and system monitor that live under this tab.
  Games: (
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
  // Display: a screen with a pulse line on it, for the overlay, the live readings and the panel
  // settings under this tab.
  Display: (
    <Icon
      path={
        <>
          <rect width="20" height="14" x="2" y="3" rx="2" />
          <path d="M8 21h8" />
          <path d="M12 17v4" />
          <path d="M6 11h2.5l1.5-3 3 6 1.5-3H18" />
        </>
      }
    />
  ),
  Library: (
    <Icon
      path={
        <>
          <rect width="18" height="18" x="3" y="3" rx="2" />
          <path d="M8 12h8" />
          <path d="M12 8v8" />
        </>
      }
    />
  ),
  Updater: (
    <Icon
      path={
        <>
          <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
          <polyline points="7 10 12 15 17 10" />
          <line x1="12" x2="12" y1="15" y2="3" />
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
};

/** Governor's own icon: a flyball governor, the spinning regulator that holds a steam engine's speed. */
export const pluginIcon = (
  <svg
    width="1em"
    height="1em"
    viewBox="0 0 24 24"
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
