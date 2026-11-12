# Supported devices

Steamling runs on Qualcomm Snapdragon handhelds. One image covers every handheld on the same
chip, and picks the right settings for yours when it boots.

**Please read this before you flash anything.** Only the Retroid Pocket 6 is a reference device.
It boots from the SD card into game mode and runs desktop mode, but it's still early (see
[Known issues](known-issues.md)). Every other handheld below is an **untested port**.
That means:

- It **builds**: the kernel, device tree and packages for it are all in this repo, and the build
  turns out an image for it.
- It **should boot**: the device support comes from [armada](https://github.com/armada-os/armada),
  where these handhelds already boot, and Steamling uses the same bootloader.
- **Nobody has run Steamling on it yet.** Expect things like a wrong screen rotation, controls
  that need remapping, or audio that needs a fix. It might work perfectly, it might not.

If you own one of these and you're comfortable flashing an SD card, you can help a lot just by
trying it and telling me what happened. See [Help test a device](#help-test-a-device) below.

## The list

### Snapdragon 8 Gen 2 (SM8550) - build with `--device sm8550` (the default)

| Handheld | Status |
|---|---|
| Retroid Pocket 6 (and TOP-DPAD) | Reference device: game mode and desktop mode both work |
| Retroid Pocket Nova | Untested port |
| AYN Odin 2 | Untested port |
| AYN Odin 2 Mini | Untested port |
| AYN Odin 2 Portal | Untested port |
| AYN Thor | Untested port (top screen only for now) |
| AYANEO Pocket ACE | Untested port |
| AYANEO Pocket DMG | Untested port |
| AYANEO Pocket DS | Untested port (top screen only for now) |
| AYANEO Pocket EVO | Untested port |
| AYANEO Pocket S (1K and 2K) | Untested port |

### Snapdragon 865 (SM8250) - build with `--device sm8250`

| Handheld | Status |
|---|---|
| Retroid Pocket 5 (both panel types) | Untested port |
| Retroid Pocket Flip 2 (both panel types) | Untested port |
| Retroid Pocket Mini | Untested port |
| Retroid Pocket Mini V2 | Untested port |
| AYN Thor Lite | Untested port (top screen only for now) |
| MANGMI Air Y Pro | Untested port |
| MANGMI Pocket Max | Untested port |
| AYANEO Pocket MICRO 2 | Untested port |

### Snapdragon 8 Gen 3 (SM8650) - build with `--device sm8650`

| Handheld | Status |
|---|---|
| AYANEO Pocket S2 | Untested port |
| KONKR Pocket FIT | Untested port |

### Snapdragon 8 Elite (SM8750) - build with `--device sm8750`

| Handheld | Status |
|---|---|
| AYN Odin 3 | Untested port |
| KONKR Pocket FIT Elite | Untested port |

## Docking

The Retroid Pocket 6 can drive a TV or monitor over USB-C, through a dock or a USB-C to HDMI
adapter that supports video (DisplayPort Alt Mode). Plug it in while game mode is running and
Steam moves to the big screen, with sound following it. Unplug it and Steam comes back to the
handheld's own screen. A headset plugged into the handheld still gets the sound while docked.

Steam remembers the resolution and refresh rate you pick for each TV in its display settings.
If the dock also charges the handheld, the power profile runs full clocks while it's connected
(see [Governor](governor.md#on-a-charger)).

## Gyro

On the Retroid Pocket 6 the gyro and accelerometer show up in Steam as part of the built-in
controller, so you can set up gyro aiming in a game's controller settings like on a Steam Deck.
The gyro calibrates itself whenever the handheld sits still for a moment.

To check it, open any game's controller settings in Steam, pick a gyro option such as **Gyro
To Joystick Camera**, and tilt the handheld.

Two settings live in `/etc/steamling/gyro.conf`, a file you create yourself. You need a terminal
for this: Konsole in desktop mode, or [SSH](governor.md#remote-access).

- **Turning the gyro off.** Run these three lines:

  ```bash
  sudo mkdir -p /etc/steamling
  echo 'STEAMLING_GYRO=0' | sudo tee /etc/steamling/gyro.conf
  sudo systemctl restart inputplumber
  ```

  To turn it back on, delete the file (`sudo rm /etc/steamling/gyro.conf`) and restart
  InputPlumber the same way.
- **Axes the wrong way round.** If tilting the handheld moves the camera the wrong way, or turns
  it when you tilt the other axis, your unit may have its sensor mounted differently.
  `STEAMLING_GYRO_CORRECTION` in the same file rotates the axes before Steam sees them, written as
  three rows of three numbers, for example
  `STEAMLING_GYRO_CORRECTION="0, 1, 0; -1, 0, 0; 0, 0, 1"`. Working out the right rows is fiddly,
  so please [open an issue](https://github.com/dvandenburgh/steamling/issues) with what you see
  instead: if it's every RP6, the fix belongs in Steamling.

## Building for your handheld

Follow the [build guide](building/README.md), but add `--device` with your chip from the list
above. For example, for a Retroid Pocket 5:

```bash
./build.sh --device sm8250
```

The image ends up in `build/image/sm8250/` (the folder is named after the chip).

## Installing on something other than the RP6

The [install guide](install.md) is written around the Retroid Pocket 6. The idea is the same on
the others: flash the bootloader (OpenABL) once from Android, then boot from the SD card. The menus
for running a script as root, and the "device model" you pick in the bootloader menu, differ
between brands. [armada's install guide](https://armadaos.dev/getting-started/flashing-to-an-sd-card/)
covers the model-specific bits for every handheld above, and the same steps apply here.

Back up your stock bootloader (the guide shows how) before you flash anything. It's your way back.

To open the OpenABL menu, hold **Volume −** while powering on, as on the RP6. The AYANEO Pocket
DMG is the exception: hold the **...** button above the volume wheel instead.

## Help test a device

If you try Steamling on one of the untested handhelds, please
[open an issue](https://github.com/dvandenburgh/steamling/issues) with:

- which handheld, and which panel version if it has more than one
- whether it booted to Steam, and how far it got if it didn't
- what works and what doesn't: screen and touch, controls, sound, Wi-Fi, sleep, fan
- the file `steamling-diag.txt`, if it's there. About a minute after every boot Steamling writes
  this report to the small partition on the SD card (the one with the `KERNEL` file), so you can
  pull the card and read it on your PC, even if the screen stayed black. It says which board
  settings were picked and what the controls, sound, Wi-Fi, battery and screen look like to the
  system.
- if you can get to a terminal (desktop mode or SSH), the output of `journalctl -b` saved to a file

A short "it booted, controls work, no sound" report is already useful. Fixes are even better:
most per-handheld settings live in one small file, `devices/<chip>/packages/steamling-bsp-<chip>/boards/<board>.conf`,
and [CONTRIBUTING.md](../CONTRIBUTING.md) explains how to test a change on a running device.

When a handheld has been tried and works well, its status here changes from "untested port" to
supported.
