# Your own base

Steamling installs two kinds of packages: the ones we build (the kernel, Mesa, gamescope, our
tools...) and everything else, which comes from Arch Linux ARM. That second set is the **base**.
Arch Linux ARM changes every day, so Steamling uses a frozen copy of it, a snapshot, so every build
and every device gets exactly the same versions.

Until now we've borrowed that snapshot from the Pocknix project. That works, but it isn't ours:
on 23 October they cut a new one at the same address, and our builds moved onto it overnight while
our settings still named the old one. This page shows how to make and host your own, so the base
only moves when you move it.

## What you need

- **The machine you already build on.** These steps were written for an x86_64 CachyOS laptop,
  but any Arch-based Linux works. It needs to be set up for building already (see
  [Building on a Linux host](linux-host.md)).
- **Somewhere public to put files.** Anything [rclone](https://rclone.org) can upload to, with a
  public web address in front of it. Cloudflare R2 is what the scripts default to: its free tier
  covers 10 GB and doesn't charge for downloads. A base is a few GB.
- **Time.** The script builds everything twice. On an x86_64 machine every Arm program runs through
  qemu, so the first build takes hours.

## 1. Set up the storage

With Cloudflare R2:

1. Create a bucket (say `steamling`) in the Cloudflare dashboard and allow public access to it,
   either with the `r2.dev` address Cloudflare offers or a domain of your own. Note the public
   address, for example `https://pub-1234.r2.dev`.
2. Create an R2 API token with read and write access to that bucket.
3. On the laptop, run `rclone config`, add a remote called `r2` of type **Amazon S3 / Cloudflare
   R2**, and paste in the token's keys and the account's endpoint.
4. Check it works: `rclone lsf r2:steamling` should run without an error.

## 2. Fill in your settings

Your settings live in one file, `config/local.conf`, which git never commits (so a Wi-Fi password in <!-- docs-check: allow -->
it stays on your laptop). Every build reads it first, so whatever you put there wins over
Steamling's defaults. Start from the example:

```fish
cp config/local.conf.example config/local.conf
```

Open it and fill in at least the two base lines, with your bucket's address from step 1:

```sh
STEAMLING_BASE_RCLONE_REMOTE=r2:steamling/repo/base
STEAMLING_BASE_URL=https://pub-1234.r2.dev/repo/base
```

The rest is optional and explained in the file: ccache, and first-boot settings like Wi-Fi, SSH,
the timezone and the root password.

## 3. Cut the base and build

From the Steamling folder, one command does the lot:

```fish
scripts/own-base.fish
```

Or let `./build.sh` start it, with any of its usual options, which then apply to both builds:

```fish
./build.sh --build-base --ssh
```

A plain `./build.sh` never touches the base; only `--build-base` does. (You can also skip
`local.conf` and pass `--remote` and `--url` to `scripts/own-base.fish` instead.)

The script:

1. Checks the laptop has what it needs, including qemu for running Arm programs.
2. Points `config/steamling.conf` at your storage.
3. Builds everything against live Arch Linux ARM (`make image`).
4. Freezes exactly what that build installed, uploads it, and pins the config to it
   (`make snapshot`).
5. Checks your public address serves the new base.
6. Builds everything again, this time from your frozen base.

If a step fails, fix the cause and run the same command again; finished work isn't redone. The
base is labelled with the date, so if you rerun on a later day, pass the first day's label (for
example `--id 20261025`), or it cuts a fresh base. When it's done, commit what it changed:

```fish
git add config/steamling.conf packages/shared/steamling-base-lock/steamling-base.lock
git commit -m "base: our own snapshot"
```

Every build after that, `make image` or `./build.sh`, uses your base. To move it forward later, say for a newer Plasma or Mesa,
run the script again; it labels each base with the date. The previous base is kept next to the new
one (as `base-prev`), so the last release can still be rebuilt.

**ccache and android-tools.** A build against live Arch Linux ARM installs ccache in the package
build environment, and the snapshot takes everything a build installed, so your base carries ccache
and package rebuilds get faster. `android-tools` (adb and fastboot) is on the list of extras the
base always hosts (`config/packages/base-extras.list`), so `sudo pacman -S android-tools` works on a
handheld for flashing and support.

## 4. Build the image

`make image` (or `./build.sh`, which is the same thing with friendlier output) builds the whole SD
card image and leaves it at `build/image/sm8550/steamling-sm8550-sd.img`. Write that file to a microSD card
as an image, with balenaEtcher, Rufus or `dd`, and follow the [install guide](../install.md). To
get a later build onto a handheld that already runs Steamling, see
[Updating Steamling](../updating.md).

You don't need a separate image-making tool. Arch's own `archiso` builds live installer ISOs for
x86_64 PCs, not SD card images for Arm handhelds. What Steamling's build does is the Arm
equivalent: it unpacks Arch Linux ARM's base system, installs packages into it the way `pacstrap`
would (running Arm programs through qemu), adds our kernel and settings, and writes the result out
as a partitioned image.

## Could desktop mode be XFCE instead of KDE?

It doesn't have to be KDE, but swapping it won't speed up games. Game mode and desktop mode never
run at the same time. Steamling starts either Steam's game mode or the desktop, and switching ends
one before starting the other. While you play, no KDE program is running, so there's nothing for
XFCE to save.

Desktop mode uses **Plasma Mobile** because it's built for a small touch screen: big touch targets,
an on-screen keyboard, and it copes with the RP6's screen being mounted sideways. XFCE could be added
as another desktop choice next to it. Steamling already lets you pick between installed desktops.
It would mean real work, though:

- XFCE still runs on X11 (its Wayland support is only partial so far), and Steamling's session
  switcher only starts Wayland desktops.
- Screen rotation, touch input and an on-screen keyboard would each need setting up separately.

What you'd gain is a smaller image, fewer updates, and a lighter desktop *while you're in desktop
mode*. If you want to check what's running while you game, connect over SSH while a game runs and
look:

```sh
ps -eo rss,comm --sort=-rss | head -20
systemctl --user list-units --state=running
```

If anything from KDE shows up there, that's a bug worth fixing on its own, whichever desktop we use.
