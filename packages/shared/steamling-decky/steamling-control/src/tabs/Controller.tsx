import { PanelSection, PanelSectionRow, ToggleField } from "@decky/ui";
import type { Dispatch, SetStateAction } from "react";
import { setLed, setLedEnabled, setLedLinked, setLedSides } from "../backend";
import { BackPaddles } from "../components/BackPaddles";
import { Calibration } from "../components/Calibration";
import { ColorControls } from "../components/ColorControls";
import { Rumble } from "../components/Rumble";
import { StickResponse } from "../components/StickResponse";
import { hsvToRgb, rgbToHsv } from "../lib/rgb";
import type { Config, LedSide, LedSideKey } from "../types";
import { t } from "../i18n";

// Stored RGB holds the full-value color; the kernel multicolor class scales each
// channel by brightness/max_brightness, so dimming is linear and the color survives.
function commit(side: LedSideKey, hsv: [number, number, number], brightness: number, setConfig: Dispatch<SetStateAction<Config | null>>, reload: () => void) {
  const [r, g, b] = hsvToRgb(hsv[0], hsv[1], 100);
  setLed(side, r, g, b, brightness)
    .then((next) => setConfig((cur) => (cur ? { ...cur, led: next } : cur)))
    .catch(() => reload());
}

function sideHsv(side: LedSide): [number, number, number] {
  return rgbToHsv(side.r, side.g, side.b);
}

type TabProps = {
  config: Config;
  setConfig: Dispatch<SetStateAction<Config | null>>;
  reload: () => void;
};

export function Controller(props: TabProps) {
  return (
    <>
      <Calibration />
      <StickResponse />
      <BackPaddles />
      <Rumble />
      {props.config.led.available && <StickLights {...props} />}
    </>
  );
}

function StickLights({ config, setConfig, reload }: TabProps) {
  const led = config.led;
  const leftHsv = sideHsv(led.left);
  const rightHsv = sideHsv(led.right);

  const commitLeft = (hsv: [number, number, number], brightness: number) => commit("left", hsv, brightness, setConfig, reload);
  const commitRight = (hsv: [number, number, number], brightness: number) => commit("right", hsv, brightness, setConfig, reload);
  const commitBoth = (hsv: [number, number, number], brightness: number) => commit("both", hsv, brightness, setConfig, reload);

  return (
    <>
      <PanelSection title={t("STICK LIGHTS")}>
        <PanelSectionRow>
          <ToggleField
            label={t("Enable")}
            checked={led.enabled}
            onChange={(value) =>
              setLedEnabled(value)
                .then((next) => setConfig((cur) => (cur ? { ...cur, led: next } : cur)))
                .catch(() => reload())
            }
          />
        </PanelSectionRow>
        <PanelSectionRow>
          <ToggleField
            label={t("Link Left & Right")}
            description={t("Match both sticks to the same color.")}
            checked={led.linked}
            disabled={!led.enabled}
            onChange={(value) =>
              setLedLinked(value)
                .then((next) => setConfig((cur) => (cur ? { ...cur, led: next } : cur)))
                .catch(() => reload())
            }
          />
        </PanelSectionRow>
        {led.sidesAvailable && (
          <PanelSectionRow>
            <ToggleField
              label={t("Side Lights")}
              description={t("Match the side lighting to the sticks.")}
              checked={led.sides}
              disabled={!led.enabled}
              onChange={(value) =>
                setLedSides(value)
                  .then((next) => setConfig((cur) => (cur ? { ...cur, led: next } : cur)))
                  .catch(() => reload())
              }
            />
          </PanelSectionRow>
        )}
      </PanelSection>

      {led.enabled && (
        led.linked ? (
          <PanelSection title={t("BOTH STICKS")}>
            <ColorControls zone="both" hsv={leftHsv} brightness={led.left.brightness} onCommit={commitBoth} />
          </PanelSection>
        ) : (
          <>
            <PanelSection title={t("LEFT STICK")}>
              <ColorControls zone="left" hsv={leftHsv} brightness={led.left.brightness} onCommit={commitLeft} />
            </PanelSection>
            <PanelSection title={t("RIGHT STICK")}>
              <ColorControls zone="right" hsv={rightHsv} brightness={led.right.brightness} onCommit={commitRight} />
            </PanelSection>
          </>
        )
      )}
    </>
  );
}
