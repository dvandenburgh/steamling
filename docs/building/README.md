# Building Steamling

This guide takes you from nothing to a Steamling SD card image you can flash. You don't need to
know Linux. Copy each command, paste it into the terminal, press Enter, and wait for it to finish
before moving on.

If you already know your way around, [advanced.md](advanced.md) has every option and target.

## What you need

- **A PC** running Linux, or Windows 10/11 (we'll set up Linux inside it). Any reasonably modern
  64-bit PC works. 16 GB of RAM is comfortable; 8 GB works, just slower.
- **About 100 GB of free disk space.**
- **An internet connection.** The build downloads a few gigabytes.
- **Time.** The first build compiles everything from source, and on a normal PC that takes a long
  time: plan on leaving it running overnight, possibly longer. Later builds only redo what
  changed, so they're much faster.
- **A microSD card** (128 GB or bigger is best) and a way to plug it into your PC.

## Step 1: Get a Linux terminal

**On Windows:**

1. Click Start, type **PowerShell**, right-click it and choose **Run as administrator**.
2. Paste this and press Enter:

   ```powershell
   wsl --install -d Ubuntu-24.04
   ```

3. Restart the PC if it asks you to.
4. Open **Ubuntu 24.04** from the Start menu. The first time, it asks you to pick a username and
   password. This is your Linux password; you'll need it in a minute. (When you type a password
   in a terminal nothing shows up on screen. That's normal, just type it and press Enter.)

Everything from here on happens in that Ubuntu window. If you get stuck on the Windows side,
[wsl.md](wsl.md) goes into more detail.

**On Linux:** open your terminal app. Ubuntu, Debian, Fedora and Arch (and distros based on them)
all work.

## Step 2: Install git

Git is the tool that downloads the Steamling source code.

On **Ubuntu or Debian** (this includes Windows users from Step 1):

```bash
sudo apt update && sudo apt install -y git
```

On **Fedora**:

```bash
sudo dnf install -y git
```

On **Arch**:

```bash
sudo pacman -S --needed git
```

It will ask for your password. Type it and press Enter.

## Step 3: Download Steamling

```bash
cd ~
git clone https://github.com/dvandenburgh/steamling
cd steamling
```

This puts the source in a folder called `steamling` in your home folder. (On Windows, make sure
you're doing this in the Ubuntu window, not in a Windows folder. Building from `C:` doesn't work.)

## Step 4: Build it

```bash
./build.sh
```

That's the whole build in one command. Here's what to expect:

- It asks for your password once, because some steps need admin rights.
- The first time, it installs the tools it needs by itself. Let it.
- The bottom line of the terminal shows what it's doing and roughly how long is left. The first
  estimate is a guess; it gets accurate on later builds.
- Lots of text will scroll past. That's fine. You only need to worry if it stops with a red
  **error** line.

If the build gets interrupted (you closed the window, the PC restarted, Windows Update happened),
just open the terminal again and run the same thing:

```bash
cd ~/steamling
./build.sh
```

It picks up where it left off instead of starting over.

### Put your Wi-Fi in the image (recommended)

Steam needs the internet to sign in, so it's easiest if the handheld is online from its very first
boot. Give the build your Wi-Fi name and password and it joins your network on its own, before
Steam starts:

```bash
./build.sh --wifi "YourNetworkName" --wifi-psk "YourPassword" --wifi-country US
```

Use your own two-letter country code (US, GB, DE...); 5 GHz networks need it. Add `--ssh` too if
you'd like to log in from your PC. Without these, you pick a network in Steam's own setup on the
first boot instead.

### Building for a handheld other than the RP6

`./build.sh` on its own builds for the Snapdragon 8 Gen 2 handhelds (the Retroid Pocket 6 and
friends). For anything else, add your handheld's chip, which you'll find in
[Supported devices](../devices.md). For example, for a Retroid Pocket 5:

```bash
./build.sh --sm8250
```

Keep in mind every handheld besides the RP6 is an untested port. In the next steps, swap
`sm8550` in the file names for your chip.

## Step 5: Find your image

When it finishes you'll have an image file here:

```
~/steamling/build/image/sm8550/steamling-sm8550-sd.img
```

**On Windows**, copy it somewhere easy to find, like your Downloads folder. Replace `YOURNAME`
with your Windows username:

```bash
cp ~/steamling/build/image/sm8550/steamling-sm8550-sd.img /mnt/c/Users/YOURNAME/Downloads/
```

## Step 6: Flash it

1. Download and install [balenaEtcher](https://etcher.balena.io/) on your PC.
2. Put the microSD card in your PC.
3. Open balenaEtcher, choose **Flash from file**, pick `steamling-sm8550-sd.img`, choose your SD
   card as the target, and click **Flash**.

Double-check you picked the SD card and not another drive. Flashing wipes whatever is on the target.

Then follow the [install guide](../install.md) to set up your handheld and boot Steamling.

## Good to know

- **Default password.** The image's `root` and `deck` password is `root`. Change it after your
  first boot (the install guide shows how).
- **More options.** Run `./build.sh --help` to see them all, or check [advanced.md](advanced.md).
- **Updating your copy later.** To build the newest version, run:

  ```bash
  cd ~/steamling
  git pull
  ./build.sh
  ```

## Something went wrong?

- Look up the error in [troubleshooting.md](troubleshooting.md). Most common problems are in there.
- Running out of memory shows up as a random "Killed" error. On Windows, [wsl.md](wsl.md#2-give-wsl-enough-memory-and-disk)
  shows how to give Ubuntu more memory.
- Still stuck? Open an [issue on GitHub](https://github.com/dvandenburgh/steamling/issues), paste
  the last 30 or so lines from the terminal, and say what kind of PC you're on.

## More detail

- [advanced.md](advanced.md): how the build works, every option, building single packages
- [linux-host.md](linux-host.md): setting up a Linux build machine by hand
- [wsl.md](wsl.md): Windows and WSL2 in depth
- [troubleshooting.md](troubleshooting.md): common errors and what they mean
- [own-base.md](own-base.md): building from live Arch Linux ARM, and hosting your own frozen base
- [publishing.md](publishing.md): putting out a release, the package repo and SD images
- [updating-from-your-pc.md](updating-from-your-pc.md): putting your own build on a handheld without reflashing
