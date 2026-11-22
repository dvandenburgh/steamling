# Contributing to Steamling

Contributions are very welcome. Steamling is maintained by one person with a small pile of
hardware, so the most valuable thing a PR can bring is **evidence it works on a real device**
and **instructions that let me reproduce that on mine**.

Questions, ideas, or "is this worth doing?" chats: the
[GitHub issue](https://github.com/dvandenburgh/steamling/issues). For anything large
(a new device family, a new session, a kernel bump, a new packaging approach), open an issue
first so we can agree the shape before you spend the time.

Especially welcome:

- **Reports from the untested handhelds.** If you own one of the handhelds marked "untested
  port" in [docs/devices.md](docs/devices.md), trying it and telling me what happened is the
  single most useful thing right now, even if all you can say is "it booted".
- **Emulator configs** that you have dialled in on a device.
- **Governor features and fixes.**
- **Docs corrections** - these need no hardware and no build.

## Contents

- [Ground rules](#ground-rules)
- [Where changes go](#where-changes-go)
- [Building](#building)
- [Testing on a device](#testing-on-a-device)
- [What your testing should cover](#what-your-testing-should-cover)
- [What the PR must contain](#what-the-pr-must-contain)
- [Package rules](#package-rules)
- [Requesting a package](#requesting-a-package)
- [Commits and PR hygiene](#commits-and-pr-hygiene)
- [AI assistance](#ai-assistance)
- [Review and merge](#review-and-merge)

## Ground rules

1. **One topic per PR.** A fix, a feature, or a config set. Not three.
2. **Test on hardware, or say plainly that you could not.** Untested is acceptable when
   declared and justified ("no RP6 to hand"). Silently untested is not.
3. **Tell me how to test it.** Every PR includes reproduction steps I can follow on my
   device. This is a hard requirement, see
   [What the PR must contain](#what-the-pr-must-contain).
4. **Bump `pkgrel`** when you change what a package ships, otherwise a handheld updating from
   a new build ([docs/building/updating-from-your-pc.md](docs/building/updating-from-your-pc.md)) or the package repo never picks your change up.
5. **Fixes go in robust locations.** A change that only survives until the next `make sync`,
   the next session restart, or the next reboot is not a fix. See
   [Where changes go](#where-changes-go).

## Where changes go

| Path | What lives there |
|---|---|
| `packages/shared/<pkg>/` | SoC-neutral packages, built once for every device. Most contributions land here. |
| `packages/soc/<pkg>/` | Packages built per SoC family (GPU stack, emulators, kernels); a `socs` file names the families or says `all`. |
| `devices/<soc>/` | Per-SoC-family and per-board facts: `profile.conf`, compiler tuning, the device metapackage, BSP package, InputPlumber configs. `devices/README.md` says where a new file goes. |
| `kernel/<soc>/` | Committed kernel inputs: pinned version, patch series, config, dts. See `kernel/README.md`. |
| `kernel/common/patches/` | Our SoC-neutral kernel patches, applied to every SoC. |
| `scripts/` | The build harness (`build-*.sh`, `lib.sh`, `stage-repo.sh`, ...). |
| `overlay/` | Image-only seeds no package can own: the deck user's home files and `/etc/plymouth/plymouthd.conf` (plymouth's own file). Programs, units, hooks and system config go in a package. |
| `config/` | Global build config: `steamling.conf`, base package lists (`config/packages/`). |
| `docs/` | User-facing guides. |
| `.github/` | Issue and PR templates, the CI workflow. |
| `.githooks/` | Git hooks; `pre-commit` runs the doc check. |
| `build/` | Build output (gitignored): rootfs, images, `localrepo/<soc>` and `localrepo/shared`. |
| `vendor/` | **Do not edit.** Regenerated wholesale by `make sync` from ROCKNIX. |

Three rules that catch most first-time contributors:

- **Kernel config changes go in a delta**, not in `kernel/<soc>/config` - that file is a
  synced ROCKNIX snapshot and `make sync` overwrites it. Use `kernel/<soc>/config-delta` for
  one chip, or the delta block in `scripts/build-kernel.sh` for every chip.
- **Anything in `overlay/` or the image scripts only reaches people who reflash.** A handheld
  updating from a new build with `pacman -Syu` never sees it. If a fix needs to reach existing installs, it belongs in a
  package with a bumped `pkgrel`. If it genuinely cannot, say so in the PR.
- **Runtime state that a session or service can clobber must be re-asserted** where it will
  stick (a systemd unit, the session launch path), not set once at install time.
- **A new Arch Linux ARM package is not installable on existing devices until it is hosted
  in the frozen base.** Installs are locked to the base (`[steamling-base]`), so `pacman -S <name>` fails
  until I add it. List the name in `config/packages/base-extras.list`, say so in the PR, and
  I host it with `make extend-base` (its dependencies must already be in the base) or at the
  next base cut.

## Building

You do **not** need to build a full image to contribute. Match the smallest thing that
covers your change:

**Anywhere (macOS, x86 Linux, no root):**

```bash
make check      # preflight: validates the harness and any built artifacts
make help       # every target
git config core.hooksPath .githooks   # once per clone: the doc check runs before each commit
```

**Governor frontend** (any host with Node, no aarch64 needed):

```bash
cd packages/shared/steamling-decky/steamling-control
npm ci
npm run build         # regenerates dist/index.js - this IS committed, see Package rules
npx tsc --noEmit      # must be clean
```

**A single package** (needs a **Linux host with root**: aarch64, or x86_64 / WSL2 through
qemu-user - see [docs/building/](docs/building/README.md)):

```bash
sudo make packages PKG="steamling-decky"    # -> build/localrepo/shared/ (per-SoC packages: build/localrepo/<soc>/)
```

**A full image** (same Linux host with root; the kernel build is 1-2 hours the first time):

```bash
./build.sh              # every step, asking sudo once -> build/image/<soc>/ (--ssh: SSH on)
```

This tree builds four SoC families: `sm8550` (the Retroid Pocket 6, the reference board, and the default), `sm8250`, `sm8650` and `sm8750`. `STEAMLING_EMULATION=1`
(`--emulation`) bakes the emulation layer into the image.

Packages compress as `.pkg.tar.zst` (older ones as `.pkg.tar.xz`), so glob `*.pkg.tar.*`.
Handhelds update Steamling's own packages from its package repo on GitHub
([docs/building/publishing.md](docs/building/publishing.md) covers putting packages there). To try
your own changes, update a handheld from your own build ([docs/building/updating-from-your-pc.md](docs/building/updating-from-your-pc.md)).

## Testing on a device

The normal loop is **build the package, copy it over, `pacman -U`, exercise it**. You do not
need to reflash an image for a package change. SSH is off by default: turn it on in Steamling
Control (Library → Remote access) or Steamling Tools, or build your image with `--ssh`. Log in as
`deck`; root can't log in over SSH.

```bash
# on the build host
scp build/localrepo/shared/steamling-decky-*.pkg.tar.* deck@steamling:/tmp/

# on the device (default password for root and deck is 'root')
sudo pacman -U /tmp/steamling-decky-*.pkg.tar.*
sudo systemctl restart <the-unit-you-touched>      # if applicable
journalctl -b -u <the-unit-you-touched>            # check it came up clean
```

When you've rebuilt several packages, serving the whole build and running `sudo pacman -Syu` on the
device is quicker: see [docs/building/updating-from-your-pc.md](docs/building/updating-from-your-pc.md).

**Keep a rollback.** Images don't carry a copy of every package, so keep the old package
yourself: copy it out of `build/localrepo/` before you rebuild, or build your test image with
`STEAMLING_IMAGE_PKG_CACHE=1` so every installed package stays in `/var/cache/pacman/pkg/`
(anything pacman has updated since is there either way). `pacman -U <old-file>` puts it back if
the new one misbehaves. A reboot back into a known-good state beats debugging a wedged session.

Notes that will save you an hour:

- **The Steam session runs as the `deck` user (uid 1001)**, not root. If you are poking at
  session state over SSH you need `XDG_RUNTIME_DIR=/run/user/1001`.
- **Never `scp` over a script that is currently executing.** Bash re-reads the file by offset
  and resumes in the middle of the new contents. Copy to `/tmp` and `mv` into place.
- **`scp`ing a script does not install its dependencies.** Install those separately, and make
  sure any new dependency is declared in the `PKGBUILD` before you submit.
- **Governor can be iterated without building a package**: copy your plugin directory
  over `/home/deck/homebrew/plugins/SteamlingControl` (`chown -R deck:deck` it) and reload the
  plugin. Do not restart the Decky loader mid-session. Note that
  `steamling-decky-sync.service` re-copies the OS-shipped plugin from `/usr/share/decky-plugins`
  on every boot, so a hand-copied plugin is replaced at reboot - fine for iteration, but the
  final verification must be from an installed package.
- **No device or no Linux host?** Still submit. Docs and configs need neither. For code, say
  what you could not test and I will run it.

## What your testing should cover

Not everything applies to every PR. Cover what is relevant, and say which items you skipped.

1. **The happy path, on named hardware.** Which device, which SoC family, and how you
   installed it (`pacman -U` a built package, hand-copied files, or a fresh image).
2. **Cold boot.** Reboot and confirm the behaviour survives, state restores, and the unit
   starts clean in `journalctl -b`. A feature that only works until you power off is not done.
3. **The update path, not just a fresh image.** Confirm the change actually arrives via
   `pacman -U` on an existing install with the bumped `pkgrel`. If the change is image-only,
   say so explicitly.
4. **Hardware that is absent or not yet probed.** A driver can fail to bind, or a node can be
   missing from a devicetree revision. Probe for the thing and degrade quietly when it is missing; never error the
   session. If you cannot test the absent-hardware path on hardware, at least show the code
   path that handles it.
6. **Failure paths.** No network, missing config file, service disabled, permission denied.
   Especially: anything gated behind Decky or the network can be late or never arrive, so a
   feature that depends on it should not be the only thing restoring important state.
7. **Neighbouring features.** Exercise the rest of the tab, service, or script you touched to
   show you did not regress it.
8. **Game mode reality**, for anything in the Steam session. It must be **fully
   gamepad-navigable** (no touch-only or mouse-only controls), readable at handheld distance,
   and it must not steal focus from the game.
9. **Perf claims need numbers.** Before and after, same scene, same settings, from MangoHud or
   an fps counter. Two traps: `ps` `%CPU` is a **lifetime average**, not current load, and a
   paused or menu scene hides jitter.
10. **Kernel changes**: boots on real hardware, no new errors in `dmesg`, suspend/resume still
    works, and the patch series still applies from a clean tree.
11. **Emulator configs**: emulator version, the exact ROM or title you tested, before/after
    behaviour, and any CPU core pinning (`taskset`) the emulator needed to perform well.

## What the PR must contain

A PR description with four sections. `.github/PULL_REQUEST_TEMPLATE.md` fills these in for
you.

**What** - what changes, in a couple of sentences, and why.

**How** - the approach, and anything non-obvious a reviewer would otherwise have to
reverse-engineer. Call out deliberate choices that look wrong at a glance.

**Tested** - device, SoC family, install method, and what you actually exercised, mapped to
the list above. Include what you could **not** test and why.

**How to test** - **required.** Step-by-step instructions I can follow on my own device to
reproduce your result. Assume I have the repo and a build host but know nothing about your
change. Include:

- the exact build command for the affected package (or "docs only, no build");
- the install and restart commands;
- what to click, run, or launch, in order;
- **what I should see** if it works, and what the old behaviour looked like;
- any setup your test needs (a specific game, ROM, emulator, SD card state, a device with
  particular hardware, a network condition);
- how to get back to a known-good state if it goes wrong.

Concretely:

```markdown
## How to test

    sudo make packages PKG="steamling-decky"
    scp build/localrepo/shared/steamling-decky-*.pkg.tar.* deck@steamling:/tmp/
    ssh -t deck@steamling 'sudo pacman -U /tmp/steamling-decky-*.pkg.tar.* && sudo reboot'

1. Boot to game mode, open the QAM, Governor -> Controller -> Stick Lights.
2. Move the Brightness slider to ~10%. Expected: the rings dim smoothly and stay the
   chosen hue. Before this change the bottom third of the slider was nearly dead and
   0% lost the colour permanently.
3. Reboot. Expected: the rings come back at the same colour and brightness.

Rollback: `pacman -U steamling-decky-<old>.pkg.tar.*` (the package I was on before)
```

"It works on my device" without these steps means the PR sits until I can work out how to
check it, which is the single biggest reason a PR stalls.

## Package rules

- **Bump `pkgrel`** whenever a package's shipped contents change. Without it, `pacman -Syu`
  from a new build is a no-op on a handheld that already runs Steamling, and only fresh images get
  your work. Bump `pkgver` only for
  an upstream version change, and reset `pkgrel=1` when you do.
- **Never ship different contents under an existing package version.** A handheld that already
  has that version won't take the new one. In practice this means: always bump, never quietly
  rebuild.
- **Committed build output must be reproducible.** `packages/shared/steamling-decky/steamling-control/dist/`
  is committed and I rebuild it from your sources during review; it should come out
  byte-identical with the pinned toolchain (`npm ci && npm run build`), and `npx tsc --noEmit`
  should be clean. Commit `dist/index.js` and `dist/index.js.map` alongside the `src/` change.
- **Patch series**: numbered files in the package directory, added to `source=()` with
  matching checksums, applying cleanly against the pinned base. If you touch a component
  with a row in `PATCHES.md`, update that row: what it carries now, plus anything
  deliberately not taken (one-clause reason). A dropped patch gets no entry beyond its
  number on the row's retired list (kept when the PKGBUILD says numbers are never reused)
  and, only where a sync or rebase would bring it back, a one-clause "stays dropped" note;
  the commit message says why.
- **License**: a package you author for Steamling declares `license=('GPL-2.0-or-later')`.
  One that repackages third-party content keeps the upstream license and names it in a
  comment on the same line (`license=('zlib')   # Valve's DXVK build, repackaged`). `make check`
  enforces both.
- **New dependencies** should come from the Arch Linux ARM repos or a package in this tree. Flag anything
  large - image size matters on a handheld.
- **A new package name needs a `depends=` edge** from the layer metapackage that owns it
  (`steamling-core`, `steamling-{steam,desktop,emulation}-full`) or from `steamling-device-<soc>`,
  in the same PR. `pacman -Syu` never installs a name nothing depends on, so without the edge
  only fresh images get it. Renaming a package needs `replaces=` + `conflicts=` for the old
  name, or updating handhelds end up with both.
- **A `replaces=` or `conflicts=` entry in a `packages/shared/` PKGBUILD** acts on every SoC's
  devices in one update (`replaces=` uninstalls the old package on `-Syu`), so each entry gets
  a row with its reason in `scripts/shared-conflicts.allow`
  (`<package dir> :: <field>=<entry> :: <reason>`). `make check` fails on an entry without a row
  and on a row whose entry is gone.
- **A device.conf consumer's fallback** (`${STEAMLING_<key>:-<value>}`) is the RP6 value for a
  key devices/README.md marks required and 0 or empty for an optional one; an exception gets a
  row with its reason in `scripts/fallbacks.allow` (`<key> :: <reason>`). `make check` fails on
  a fallback that breaks the rule without a row and on a row that matches no fallback.
- **Shared code does not name a chip.** A code line outside `devices/`, `kernel/`, the family
  docs and `packages/soc/<name>-<soc>/` that names an SoC (`sm8550`) handles today's chips and
  mishandles the next one. Make it chip-neutral (read device.conf or the build's `SOC`); a
  deliberate exception gets a row in `scripts/soc-ids.allow` (`<path glob> :: <regex> ::
  <reason>`). `make check` fails on an uncovered chip id and on a row that matches nothing, so
  fixing a leak deletes its row.
- **Do not touch `vendor/`.** `make sync` regenerates it.

## Requesting a package

The locked base is a curated snapshot, not a mirror of Arch. Hosting a package means keeping
it resolvable at every base cut and answering bug reports about it, so requests are judged on
what the package does for the device as a handheld, not on size or on whether Arch carries it.
Open one with the **Package request** issue form; it asks for exactly this.

| The package is... | Answer | Examples |
|---|---|---|
| in Arch Linux ARM, its dependencies already in the base, and it serves the handheld | hosted as an opt-in extra at the next base cut; `pacman -S <name>` then works on a locked device | `tailscale`, `samba` |
| not in Arch Linux ARM, or needs patches | only if it is part of what Steamling does: games, emulation, the two sessions, the device itself | `mesa`, `fex-emu` |
| anything else | install it yourself, unsupported: Flatpak via Discover, `pacman -U` straight from the Arch Linux ARM mirror, `makepkg` from the AUR (`base-devel` and `git` are in the base), or `sudo steamling-base rolling` for live Arch Linux ARM | editors, toolchains, AUR helpers |

AUR helpers (`yay`, `paru`) are not hosted: AUR recipes mostly target x86_64, self-built
packages break silently when the base rotates, and a tool whose job is updating everything
works against the locked base.

## Commits and PR hygiene

- **Subject**: `area: concise summary`, lowercase after the colon, under about 65 characters.
  Areas in use: `build`, `kernel`, `image`, `sd-image`, `steam`, `desktop`, `emulation`,
  `input`, `audio`, `wifi`, `suspend`, `perf`, `gamescope`, `mesa`, `fex-emu`, `bsp`,
  `devices`, `repo`, `ci`, `docs`, `cleanup`, or a package name.
- **Milestone granularity.** Squash the "try X", "revert X", "fix typo" churn before you
  submit. A commit should be a complete, verified change.
- **Rebase on `main`** rather than merging it in, and re-test after the rebase.
- **Code comments: 2 to 4 lines, and only the WHY.** Status, plan, and validation narrative do
  not belong in comments or commit bodies. A comment is self-contained: it may point at a file
  in this repo, never at anything outside it. `make check` enforces the mechanical part
  (`scripts/check-comments.py`): a repo path a comment names must exist, and a comment carries
  no lineage or validation wording, no version, pkgrel, commit hash or date, and no pointer to
  documents outside the repo. An exception
  whose number or path IS the mechanism goes in `scripts/check-comments.allow`
  (`<glob> :: <regex>` or `<glob> :: <kind> :: <regex>`, one per line).
- **CI must be green.** The `lint` job runs `bash -n` over every script and `PKGBUILD`,
  resolves each device profile chain, checks that the kernel cmdline lives only in
  `profile.conf`, and checks the docs against the tree (`scripts/check-docs.sh`:
  every path and `make` target they name exists, layout blocks match their dirs, structural
  READMEs carry no versions or counts; a line that must keep one carries
  `docs-check: allow`) and the code comments against the tree (`scripts/check-comments.py`,
  see above). A doc that describes what you changed moves in the same PR. It is fast; there is no excuse for a red PR.
- **No unrelated reformatting.** It makes the real change unreviewable.

## AI assistance

Using an AI assistant is fine, and the maintainer is open about using one too. Three
conditions:

- **Say so in the PR.** It genuinely helps me target the review, and it has done so before.
- **You understand what you submit.** That means the code itself, what it changes on the
  device, and what else it might affect. If you cannot answer "why this way?", it is not ready.
- **It is tested on hardware.** Plausible-looking code that has never run is worse than no PR.

## Review and merge

I read every PR. Device-testable changes merge **after I have run them on my own hardware**,
so expect a few days, and expect specific review comments - `pkgrel` bumps, per-device
coverage, whether a fix lives somewhere durable. If a requested change is outside your comfort
zone (systemd wiring, packaging, the kernel), say so and I will do that part; a PR does not
have to be perfect to be worth merging.

Once merged, the change ships to users as a package update in the next release, or in the next
image if it is image-only.

Steamling is [GPL-2.0-or-later](LICENSE.md). By contributing you agree your work ships under
the same licence.
