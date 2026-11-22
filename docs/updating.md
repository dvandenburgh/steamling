# Updating Steamling

Steamling's own packages (the kernel, Mesa, gamescope, Governor and the rest) come from
Steamling's package repo, so a handheld updates over the internet: **Governor → System → Check for
Updates** in game mode, the **Steamling Updater** app in desktop mode, or `sudo pacman -Syu` in a
terminal. An image built from a current Steamling checkout already knows about the repo. A
handheld set up before the repo existed needs [switching over once](#switching-to-the-package-repo).

If you build Steamling yourself, there are two more ways to get your own build onto a handheld:

- **Reflash** the SD card with the new image. Simple, but it wipes the card, so back up your saves
  and anything else on it first.
- **Update over your home network** from the PC you build on. Nothing is wiped and it takes a few
  minutes. Most of this page walks through it.

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

Answer `Y` to the list, and to any question about replacing a package. If it asks which of
several packages should provide something (it does this once after building with `--cores`),
press Enter: the first answer is the one from your build. Every update takes a
[snapshot](snapshots.md) first, so if something breaks, `sudo steamling-rollback` puts the system
back the way it was. If you rebuilt the kernel, the boot image is redone for you during the update.

### Next time

Steps 1, 2 and 4 again: rebuild, start the server, `sudo pacman -Syu`. The handheld remembers
your PC.

On a handheld built from live Arch Linux ARM, `pacman -Syu` also brings in whatever Arch has
updated since. The build refuses packages that wouldn't fit together, but if an update misbehaves,
roll it back.

### Undoing it

To stop updating from your PC and go back to the package repo, see the next section.

## Switching to the package repo

A handheld from an image built before the package repo existed, or one you've been updating from
your PC, doesn't update from the repo yet. To switch it over:

1. If it has never been updated from your PC, do that once first, following the steps above. That
   brings in a `steamling-base` package that knows where the repo is.
2. Then, over SSH:

   ```bash
   sudo steamling-base repo
   sudo pacman -Syu
   ```

The first command replaces the sections pointing at your PC with the repo's, and trusts the key the
repo's packages are signed with. The update after it usually has little or nothing to do. From then
on the handheld updates from the repo, and you can stop the server on your PC.

## Governor's System tab and Steamling Updater

**Governor → System**, the **Steamling Updater** app in desktop mode and
`sudo pacman -Syu` all do the same thing: install updates from the repos the handheld knows about.
That means:

- Steamling's own packages from the package repo, or from your PC if you've pointed the handheld
  there as above
- the Arch Linux ARM side from Steamling's frozen base, which only changes when a newer Steamling
  release moves the base (an image you built from live Arch Linux ARM gets Arch's latest packages
  instead)

The **Roll Back Last Update** button there undoes the last update, whichever way you ran it.

## Steam's update channel

Steam's **Settings → System → Beta Participation** has two drop-downs:

- **Steam Client Update Channel** switches the Steam client between **Steam Stable** and
  **Steam Beta**. Steam restarts onto the channel you pick, and it stays on it across reboots.
- **OS Update Channel** always reads **stable** and has nothing else to pick. Steam's own system
  update check isn't connected to Steamling: system updates come through Governor → System, as
  above.

![Steam's Beta Participation settings: OS Update Channel on stable and Steam Client Update Channel on Steam Stable](images/steam-settings-update-channel.jpeg)
