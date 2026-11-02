# Install Steamling

These steps are written for the Retroid Pocket 6. On the other handhelds (all untested ports,
see [Supported devices](devices.md)) the idea is the same, but the Android menus and the
bootloader's device model differ; that page points to model-specific help.

Steamling runs from a microSD card. Once it is up you can [move it to internal
storage](install-to-internal.md) for faster loading.

**New to this? It's easier than it looks.** You don't need to install any other system first, root
Android, or plug the handheld into a PC. The Retroid Pocket 6 has a tool built into Android's
settings that runs a script with full permissions (**Settings → Handheld Settings → Advanced → Run
Script as Root**), and everything the bootloader needs comes on the Steamling card. So the whole
setup is: flash a card, copy one folder, tap two scripts, pick three options in a menu. About
15 minutes, done once per handheld.

**You need** a microSD card: 64 GB works but fills up fast once games are installed, so 128 GB or
larger is recommended.

## 1. Flash the SD card

Build the image yourself with the [build guide](building/README.md) (it comes out as
`build/image/steamling-sm8550-sd.img`), or grab one from the
[Releases](https://github.com/dvandenburgh/steamling/releases) page once there are some.

Write it to the card **as an image**, with [balenaEtcher](https://etcher.balena.io/), Rufus or `dd`.
Don't copy the `.img` file onto the card like a normal file: that gives you a card with one big
file on it, and the bootloader will find nothing to boot. When it's written properly, Android (or
your PC) sees a small partition on the card with a `KERNEL` file and an `openabl` folder on it.

## 2. Install the bootloader (OpenABL)

The stock bootloader only boots Android. OpenABL replaces it with one that can boot Linux from the
SD card or internal storage. You do this **once per handheld**, from Android, with the built-in
**Run Script as Root** tool; everything it needs is on the Steamling card. (Its predecessor was
called the ROCKNIX ABL. If you already flashed that one, it still works, but update to OpenABL from
this card: the old one has different menus.)

Charge the handheld to at least half first. A power cut while the bootloader is being written
leaves a device that needs a PC to recover.

1. Put the flashed card in and let Android start. Copy the `openabl` folder from the card to the
   top level of Android's internal storage. (Cards made before October 2026 call it `rocknix_abl`;
   either works.)
2. Open **Settings → Handheld Settings → Advanced → Run Script as Root**. That's where it is on
   Retroid handhelds; AYN, AYANEO and the others put it elsewhere. Go into the `openabl` folder
   you just copied and run `backup_abl.sh`. It saves your stock bootloader as `abl_a.img` and
   `abl_b.img` next to the scripts.
3. Copy those two backups off the device, to your PC. Installing Steamling to internal storage later
   wipes Android's data, backups included, and they're your only way back to the factory
   bootloader (see [restoring the stock bootloader](install-to-internal.md#restoring-the-stock-bootloader)).
4. Back in **Run Script as Root**, run `flash_abl.sh`. It writes OpenABL to both bootloader slots.
   It won't run until step 2 has saved a backup, so you can't skip that by accident.

**Check that it took.** Power off, then hold **Volume −** while powering on. You should get the
OpenABL menu. Its **Device info** entry shows the bootloader version, which should be **1.2** or
newer. If the menu has entries called **Change boot mode** and **Set the Device** instead, that's the
old ROCKNIX ABL: run `flash_abl.sh` from this card again. OpenABL versions before 1.1.1 could reset
straight back into the menu just as they started Linux, so make sure yours is current.

Already running OpenABL and have a PC handy? Fastboot works while the OpenABL menu is open, so you
can also update it from there with the `abl_signed-SM8550.elf` in the card's `openabl` folder:

```sh
fastboot flash abl_a abl_signed-SM8550.elf
fastboot flash abl_b abl_signed-SM8550.elf
```

## 3. Boot Steamling

1. Power off and **put the card in first**. The bootloader only looks at the card when it starts,
   and the list of device models it offers comes from the card.
2. Hold **Volume −** while powering on to open the menu. Volume keys move, the power key selects.
3. Set these three:
   - **Boot mode** → **Linux**
   - **Boot source** → **SD card**
   - **Device model** → **Retroid Pocket 6** (or **Retroid Pocket 6 TOP-DPAD** if yours has the
     D-pad on top). Don't skip this one: without a device model OpenABL won't start Steamling and
     drops you straight back into the menu. A wrong model gives a black screen.
4. Optional, for your first boot: set **ABL mode** to **Verbose**. The bootloader then shows its log
   on screen while it starts Steamling, which helps a lot if something goes wrong.
5. Pick **Start**.

The menu remembers these settings, so from now on the handheld boots Steamling whenever the card is
in. The first boot into game mode can take a long while, especially from an SD card. Leave it be;
it will come up.

On the first boot, Steam walks you through a short setup: language, time zone, then your Wi-Fi
network (Steam needs the internet to sign in). When it finishes, the handheld restarts once and
then lands on the Steam sign-in screen. If you ever end up at the sign-in screen with no network,
tap the **Wi-Fi icon** at the top of the screen, pick your network there and connect, then sign in.

### If it doesn't boot

When Start doesn't work, OpenABL comes back to its menu and says why at the top, as **Start Linux
came back: …**. The menu's **Log** entry has the details. Here's what each one means:

| What you see | What it means | What to do |
|---|---|---|
| **nothing to boot** | The bootloader can't find Steamling on the card. | Check **Boot source** is **SD card**. Reseat the card, then re-write it as an image (step 1). If it still isn't found, try another card: the bootloader's own SD driver is pickier than Android's, and a plain A1 card from a known brand is the safest bet. |
| **the boot image needs a device model** | No device model is picked. | Pick **Retroid Pocket 6** under **Device model**, with the card in. |
| **Device model** has no Retroid Pocket 6 in it | The bootloader isn't reading the card. | Same as *nothing to boot*. |
| **the boot image failed** | It found Steamling but couldn't start it. | Open **Log**; the last lines say why. Take a photo of them for a bug report. |
| It restarts straight back into the menu, with no message | The bootloader crashed while starting Linux. | Check **Device info**. If the version is older than 1.2, update OpenABL (step 2). |
| The screen goes black and stays black | Linux started. | Give the first boot 10 minutes. If it never comes up, check **Device model**. |
| Android starts instead | **Boot mode** is set to **Android**, or Volume + was held. | Set **Boot mode** back to **Linux**. |

> [!IMPORTANT]
> **Then change the default password.** The `deck` user's password (and root's) is `root` and
> publicly known: run `passwd` (and `sudo passwd root`) in a terminal. SSH is off by default.

## Handy to know

- **Screenshots.** Hold the **Home** button and press **R1**, in a game or in Steam's menus. Steam
  keeps them under **Media** in its main menu. To copy them to a PC, turn on
  [USB file transfer](governor.md#usb-file-transfer), or over SSH:
  `scp -r deck@steamling:'~/.local/share/Steam/userdata/*/760/remote/*/screenshots' .`
- **Logging in from a PC.** Turn on **Allow SSH logins** in
  [Governor → System](governor.md#remote-access), then `ssh deck@steamling`
  (or `deck@steamling.local`). Root can't log in over SSH; use `sudo` as `deck`.
- **Sleep.** A short press of the power button puts it to sleep and wakes it again; **Sleep** in
  Steam's power menu works too.

## Updating

There's no download server for Steamling, so updates don't arrive on their own. When you build a
newer version, you can either flash the new image (which wipes the card, so back up your saves
first) or send it to the handheld over your home network without reflashing.
[Updating Steamling](updating.md) walks through both.

The Steam client updates itself separately and tells you when one is available. If an update goes
wrong, see [snapshots and rollback](snapshots.md).
