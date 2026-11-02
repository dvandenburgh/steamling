import { MenuWidthSetting } from "../components/MenuWidth";
import { PanelCalibration } from "../components/PanelCalibration";
import { PerformanceOverlay } from "../components/PerformanceOverlay";
import { SystemMonitor } from "../components/SystemMonitor";

// What's on the screen: the overlay and live readings first, the panel and menu settings after.
export function Display() {
  return (
    <>
      <PerformanceOverlay />
      <SystemMonitor />
      <PanelCalibration />
      <MenuWidthSetting />
    </>
  );
}
