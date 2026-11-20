# Publishing packages and images

This page is for whoever puts out Steamling releases. Building for your own handheld doesn't need
any of it.

Three things get published, each to its own place:

| What | Where | Made with |
| --- | --- | --- |
| The frozen Arch Linux ARM base | [Steamling/base](https://github.com/Steamling/base) releases | `./build.sh --build-base` ([own-base.md](own-base.md)) |
| Steamling's own packages (kernel, Mesa, gamescope, Governor...) | [Steamling/packages](https://github.com/Steamling/packages) releases | `make stage` and `make publish` (below) |
| SD card images | the [steamling](https://sourceforge.net/projects/steamling/) project on SourceForge, linked from a draft release on [Steamling/steamling](https://github.com/Steamling/steamling/releases) | `make publish-image` (below) |

Everything here runs as you, never with `sudo`: the logins for GitHub, SourceForge and your signing
key live in your account.

## The package repo

Handhelds update Steamling's own packages from two pacman repos: `[steamling]`, one per chip family
because those packages are tuned for the chip, and `[steamling-shared]` for everything that's the
same on every handheld. On GitHub each is one release of Steamling/packages, named after its
folder: `sm8550`, `sm8250` and so on, and `shared`.

### One-time setup

1. **Log GitHub in**, with an account that can write to Steamling/packages:

   ```bash
   gh auth login
   ```

2. **Make a signing key.** Handhelds only install packages signed with it:

   ```bash
   gpg --quick-gen-key 'Steamling Packaging <you@example.com>' ed25519 sign 2y
   ```

   Back up `~/.gnupg` somewhere safe. If the key is lost, every handheld has to be told about a
   new one by hand.

3. **Tell the build about the key.** Put its email in `config/local.conf`: <!-- docs-check: allow -->

   ```sh
   STEAMLING_REPO_GPG_KEY=you@example.com
   ```

   and export the public half into the repo, where images and the `steamling-base` package pick
   it up:

   ```bash
   gpg --export --armor you@example.com > packages/shared/steamling-base/steamling-repo.gpg
   ```

   That file is public; commit it.

### The first publish

There's nothing live to compare against the first time, so each tree goes up straight from the
build's own packages:

```bash
STEAMLING_PUBLISH_FROM=localrepo make publish
STEAMLING_PUBLISH_FROM=localrepo make publish-shared
```

Do the first line once per chip family you build (`make publish DEVICE=sm8250` and so on). Then
point builds at the repo by setting this in `config/steamling.conf`, and commit it:

```sh
: "${STEAMLING_REPO_URL:=https://github.com/Steamling/packages/releases/download}"
```

Bump `pkgrel` in `packages/shared/steamling-base/PKGBUILD` in the same commit and publish
`steamling-base` the normal way (below). That package carries the address and the key, and a
handheld that was flashed before the repo existed adds the repo when it installs it. That first
update has to come from your PC ([Updating Steamling](../updating.md)); after that it updates
itself.

### Every release after that

Build as usual, then name the packages that changed:

```bash
make stage PKG="mesa gamescope"
make publish
```

`make stage` copies what's live, swaps in only the packages you named and checks the result can
actually be installed on every family. `make publish` signs and uploads it. Shared packages go the
same way with `make stage-shared` and `make publish-shared`. `DROP="name"` takes a package out of
the repo.

A published file must never change: bump `pkgrel` for every rebuild, or `make stage` refuses.

## SD card images

An image is several GB, past GitHub's 2 GiB limit for a release file, so it goes to SourceForge
and the GitHub release links to it.

One-time setup:

1. Add an SSH key to your SourceForge account (**Account Settings → SSH Settings**). Make one
   with `ssh-keygen -t ed25519` if you don't have one, and paste in `~/.ssh/id_ed25519.pub`.
2. Put your SourceForge username in `config/local.conf`: <!-- docs-check: allow -->

   ```sh
   STEAMLING_IMAGE_SOURCEFORGE_USER=your-sourceforge-username
   ```

Then, once an image is built and you've tried it on a handheld:

```bash
make publish-image
```

That compresses the image to `.img.xz`, uploads it and its `.sha256` to a folder named after the
version on SourceForge, and makes a **draft** release on Steamling/steamling with a download link
for that chip family. Run it again for each family you build; their links sit side by side. The
version and codename come from `packages/shared/steamling-base/steamling-os-release`, so bump
those first for a new release.

Nothing is public until you finish it yourself: write "What's new" on the draft and press
**Publish**. On SourceForge, click the **i** next to the newest image and make it the default
download, so the big green button gets it.
