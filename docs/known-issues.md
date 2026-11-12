# Known issues

Things that are known not to work, or not to work well yet. Something missing from this list?
Open an [issue on GitHub](https://github.com/dvandenburgh/steamling/issues).

## Steam and game mode

- **Game mode can take a long time to come up.** On first boot, or after a Steam client update,
  Steam can take a *long* while to get ready, especially when running from an SD card. The
  Steamling logo stays on screen while it does; a short black gap before the logo appears
  is normal. Leave the device alone and it will get there.
- **Steam's "Add a Non-Steam Game" dialog does not work.** Use **Governor → Files** to add
  one instead.
- **MangoHud costs a little performance.** It is fine for dialing in settings, but turn it off
  for real play. Honestly, consider this a feature: stop staring at the numbers and enjoy the
  game 😃

## Hardware

- **No battery charge limit on the Retroid Pocket 6.** Its battery firmware refuses a charge
  limit (the request times out), so Steam doesn't offer the setting and the battery always charges
  to 100%. Other handhelds that support one, like the Odin 3, get the setting in Steam.
- **Docking is new.** Moving game mode to a TV over a USB-C dock, and sound following it, are built
  for the Retroid Pocket 6 but haven't been tried on many docks and TVs yet. If yours doesn't show
  a picture, or the sound stays on the handheld, please say which dock or adapter you used.
- **Gyro on the Retroid Pocket 6 only, and through Steam Input.** The RP6's gyro works for gyro
  aiming set up in Steam's controller settings, in any game. Emulators that read motion
  themselves (motion controls in Switch, Wii U and 3DS games) don't get it yet, because they see
  Steam's virtual controller rather than the handheld's. The other handhelds' motion sensors
  aren't wired up yet. If the gyro reads its axes turned on your unit, or you'd rather have it
  off, see `/etc/steamling/gyro.conf` in [Supported devices](devices.md#gyro).

## Untested ports

Everything below applies to the handhelds marked "untested port" in
[Supported devices](devices.md). They build and should boot, but nobody has run Steamling on
them yet, so treat this list as a starting point rather than the whole story.

- **Second screens stay dark.** The AYN Thor, AYN Thor Lite and AYANEO Pocket DS show Steam on
  the top screen only; the bottom screen's touch input is switched off so it doesn't land on the
  top one.
- **Older Windows games on the Snapdragon 865 (SM8250) handhelds.** Its Adreno 650 can't run
  DXVK 3, which the bundled Protons use for Direct3D 9 to 11. Those games won't start until
  Protons built with DXVK 2 are packaged for it. Native and Direct3D 12 games are not affected.
- **AYANEO and KONKR controls.** Their controllers are switched into the right mode at boot
  (`steamling-gamepad-quirk`). Some AYANEO extras (the custom buttons, the gamepad mode switch)
  rely on drivers in armada's kernel that the SM8550 kernel here doesn't carry yet.
- **Screen settings are first guesses.** Resolution, rotation and HDR brightness for each
  handheld come from its panel driver and armada's settings. If the picture is sideways or the
  wrong size, the fix is usually one line in that handheld's board file.
