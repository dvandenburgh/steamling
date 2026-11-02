# Snapshots and rolling back an update

Before every update, Steamling saves a copy of the system called a snapshot. If an update breaks
something, you can put the system back the way it was with one button (or one command) and a
reboot.

**Rolling back never touches your games, saves or settings.** Only the system itself goes back.
If the update brought a new kernel, the old kernel comes back too.

If your storage is nearly full, the snapshot is skipped. The update still installs, you just
can't undo that one.

That covers every update, whichever way you install it: Governor's System tab, Steamling Updater,
`sudo pacman -Syu`, or a new build from your PC ([Updating Steamling](updating.md)).

## Rolling back

There are three ways to do it. They all do the same thing, so use whichever one still works:

- **In game mode:** open the Quick Access Menu, go to **Governor**, then the
  **Updater** tab, and press **Roll Back Last Update**. It shows what will be restored. Confirm,
  then press **Reboot Now**. This button only ever undoes the most recent update.
- **In desktop mode:** open **Steamling Tools** and pick *Roll back the last update...*. This
  lists every snapshot, newest first. Pick one, confirm, and reboot when it asks. Use this one
  if Steam or the plugin is the thing that broke.
  (If you booted from the SD card and also have Steamling on internal storage, *Roll back the
  INTERNAL install...* does the same for the internal copy.)
- **In a terminal** (on the device, or over SSH):

```bash
steamling-snapshots list          # show the snapshots you can go back to
steamling-snapshots status        # which one is running, which boots next, free space
sudo steamling-rollback           # go back to the newest snapshot (asks first)
sudo steamling-rollback --to 0003 # go back to snapshot 0003
sudo steamling-rollback --yes     # don't ask first (for scripts)
sudo steamling-rollback --internal --to 0003  # roll back the internal install, from the SD card
sudo steamling-snapshots prune    # delete old snapshots now (updates do this on their own)
```

### Good to know

- Each snapshot is a complete copy of the system, so `--to` jumps straight to that snapshot. You
  don't have to step back one update at a time.
- You can also jump forward. If you rolled back and want the newer system again, roll "back" to
  the newer snapshot.
- Changed your mind about a rollback? Roll back again. The system you left behind is kept until
  the next rollback, in case you want to look at it.
- After a rollback, Governor's System tab shows a *"System was rolled back"* note and hides the
  rollback button, because you're already on the older system. Your next update clears the note
  and brings the button back.
- Snapshot times are shown in your local time.

## If the device won't boot after a kernel update

Every kernel update keeps the previous kernel as a file called `KERNEL.bak`. If the device won't
boot at all and you can't get to a terminal, you can swap the old kernel back in by hand:

1. Power the device off and take out the SD card. Put it in a card reader on your PC.
   (If Steamling is on internal storage, boot a Steamling SD card instead and open the internal
   boot partition from there.)
2. Open the small boot partition (it's a FAT partition, so Windows, macOS and Linux can all read
   it). In a terminal in that folder, run:

   ```bash
   mv KERNEL KERNEL.bad
   mv KERNEL.bak KERNEL
   md5sum KERNEL > KERNEL.md5
   ```

   Don't skip the last line. The bootloader checks that file and won't boot a kernel that doesn't
   match it.
3. Put the card back and boot. The old kernel is now running with the newer system around it, so
   some things (Wi-Fi or sound, for example) may not work, but it boots. Run
   `sudo steamling-rollback` to put the rest of the system back in step with the old kernel.
