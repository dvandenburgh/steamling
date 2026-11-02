steamling - Your Games Folder
===========================

This folder (~/Emulation) is where everything goes. Copy your files into the
matching subfolder and they are picked up automatically the next time ES-DE starts.

1. ROMS -> ~/Emulation/ROMs/<system>/
   Put each game in the folder for its system, e.g.
     ROMs/snes/    Super Nintendo games
     ROMs/psx/     PlayStation 1 games
     ROMs/ps2/     PlayStation 2 games
     ROMs/switch/  Nintendo Switch games
   (One subfolder per system was created for you. Empty systems stay hidden in the
   menu until you add a game.)

   MORE ROOM ON A MICROSD CARD -> <card>/Emulation/ROMs/<system>/
   Put a microSD card in and the same folders appear on it. Games on the card
   and games here show up together in ES-DE. Take the card out and its games
   just drop off the list until it's back.
   (ES-DE reads ~/Emulation/Library, which holds links to both. Don't put games
   there: use ROMs/ here or the card's Emulation/ROMs/.)

2. BIOS FILES -> ~/Emulation/BIOS/
   Some systems need original BIOS/firmware files. Every emulator looks here.
   Exact filenames matter:
     PS2:       rename your BIOS dump to  ps2-bios.bin
     PS1:       scph5501.bin (and friends) as dumped
     Dreamcast: dc/dc_boot.bin + dc/dc_flash.bin (note the dc subfolder)
     GBA:       gba_bios.bin (optional - improves accuracy)
   If a game won't boot, it's usually a missing or misnamed BIOS - the emulator's
   error message names the exact file it wants.

3. NINTENDO SWITCH
   Steamling ships no Switch emulator. Drop your own Eden or Ryujinx build in (section 4)
   and it is set up for you: controller, fullscreen, vsync and resolution come
   pre-configured. Both need your own keys and firmware, in their own folders (not BIOS/):
     Eden:     keys prod.keys + title.keys -> ~/.local/share/eden/keys/
               firmware .nca files          -> ~/.local/share/eden/nand/system/Contents/registered/
     Ryujinx:  keys -> ~/.config/Ryujinx/system/    firmware: install it from Ryujinx's own menu
   With both dropped in, pick which one runs in ES-DE: Other Settings -> Alternative Emulators.

4. YOUR OWN EMULATOR BUILDS -> ~/Emulation/emulators/<name>/
   Every standalone emulator has a folder here. Put ONE file in it (an AppImage or a
   binary) and Steamling launches that instead of its own build, from ES-DE and from Steam
   alike, with the same pre-made settings. Remove the file to go back to the built-in one.
   Folders: eden, ryujinx, armsx2, rpcs3, vita3k, xemu, dolphin, cemu, azahar, ppsspp.

5. GET IT INTO YOUR STEAM LIBRARY
   In ES-DE, press the Favorite button on any game to star it. Starred games are
   added to your Steam library automatically (in a "Steamling" collection) - no manual
   setup. Un-star to remove it again. New/removed favorites appear next time you
   enter Game Mode.

Saves and save-states live in ~/Emulation/Saves and ~/Emulation/States, so a single
copy of this ~/Emulation folder is fully self-contained and portable.

MOVING YOUR ROMS (e.g. to an SD card): ES-DE Menu -> Other Settings -> ROM directory,
pick the new location, move the files there. Everything else follows automatically.

You (and only you) are responsible for supplying game and BIOS files you legally own.
