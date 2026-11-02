# Updating Steamling

Steamling has no download server: there's no package repo and no over-the-air updates. A new
version of Steamling comes from building it yourself. You then get it onto the handheld one of two
ways:

- **Reflash** the SD card with the new image. Simple, but it wipes the card, so back up your saves
  and anything else on it first.
- **Update over your home network** from the PC you build on. Nothing is wiped and it takes a few
  minutes. The rest of this page walks through it.

Some things update on their own either way: the Steam client updates itself and tells you when one
is ready, Decky offers its own updates, and games update through Steam as usual.

## Updating from your own build, without reflashing

You need:

- the PC you build Steamling on, on the same network as the handheld
- SSH turned on, on the handheld: build with `--ssh`, or turn on **Allow SSH logins** in
  **Governor → System → Remote access**
- a handheld already running Steamling, built from the same checkout

These steps use the RP6, whose chip family is `sm8550`, and a build PC at `192.168.1.50`. Swap in
your own: `ls build/localrepo` on the PC shows the family folder, and `ip -4 addr` (or `ipconfig`
on Windows) shows the PC's address.

### 1. Build the packages

On the PC, in your Steamling folder:

```bash
./build.sh --update
```

That builds only what changed since your last build (the kernel too, if it changed) and stops
there, with no new image. It asks for `sudo` once, like a full build. Check the end of the output:
a package that failed to build just stays at its old version on the handheld.

### 2. Share them on your network

Still on the PC:

```bash
cd build/localrepo
python3 -m http.server 8080
```

Leave that window open until the handheld has finished updating.

**Building in WSL on Windows?** The handheld can't see WSL directly. Forward the port from Windows
instead, in an **admin PowerShell** window, with the server above running:

```powershell
$wslip = (wsl hostname -I).Trim().Split(' ')[0]
netsh interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=8080 2>$null
netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=8080 connectaddress=$wslip connectport=8080
New-NetFirewallRule -DisplayName "Steamling packages" -Direction Inbound -Protocol TCP -LocalPort 8080 -Action Allow
```

The firewall rule only needs adding once. WSL's address changes every time it restarts, so run the
first three lines again after a reboot. Use the Windows PC's address (from `ipconfig`) on the
handheld.

### 3. Point the handheld at your PC (once)

Log in over SSH (`ssh deck@steamling`) and run this, with your PC's address on the first line:

```bash
PC=192.168.1.50
FAMILY=sm8550
sudo awk -v pc="$PC" -v fam="$FAMILY" '
  !done && /^\[/ && $0 != "[options]" {
    print "[steamling]\nSigLevel = Never\nServer = http://" pc ":8080/" fam "\n"
    print "[steamling-shared]\nSigLevel = Never\nServer = http://" pc ":8080/shared\n"
    done = 1
  }
  { print }' /etc/pacman.conf > /tmp/pacman.conf && sudo cp /tmp/pacman.conf /etc/pacman.conf
sudo sed -i '/^IgnorePkg/d' /etc/pacman.conf
```

This adds your PC as the first place pacman looks, so Steamling's own packages (the kernel, Mesa,
gamescope, Plasma Mobile and the rest) come from your build. The second command drops a hold that
images built from live Arch Linux ARM carry: it stopped Arch's versions replacing ours, and with
your PC listed first it's no longer needed.

Check the handheld can reach the PC. Both lines should say `200 OK`:

```bash
curl -sI http://192.168.1.50:8080/sm8550/steamling.db | head -1
curl -sI http://192.168.1.50:8080/shared/steamling-shared.db | head -1
```

### 4. Update

```bash
sudo pacman -Syu
sudo reboot
```

Answer `Y` to the list, and to any question about replacing a package. Every update takes a
[snapshot](snapshots.md) first, so if something breaks, `sudo steamling-rollback` puts the system
back the way it was. If you rebuilt the kernel, the boot image is redone for you during the update.

### Next time

Steps 1, 2 and 4 again: rebuild, start the server, `sudo pacman -Syu`. The handheld remembers
your PC.

On a handheld built from live Arch Linux ARM, `pacman -Syu` also brings in whatever Arch has
updated since. The build refuses packages that wouldn't fit together, but if an update misbehaves,
roll it back.

### Undoing it

To stop updating from your PC:

```bash
sudo sed -i '/^\[steamling\]$/,+3d;/^\[steamling-shared\]$/,+3d' /etc/pacman.conf
```

## Governor's System tab and Steamling Updater

**Governor → System**, the **Steamling Updater** app in desktop mode and
`sudo pacman -Syu` all do the same thing: install updates from the repos the handheld knows about.
On a fresh image that means the Arch Linux ARM side only, never Steamling's own packages:

- an image built on Steamling's frozen base finds nothing new until a newer build moves the base
- an image built from live Arch Linux ARM gets Arch's latest packages, with ours held back

Once your handheld points at your PC as above, they install your new build too. The **Roll Back Last Update** button there undoes the last update, whichever way
you ran it.
