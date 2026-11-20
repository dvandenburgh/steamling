# steamling: Arch-ARM dual-session distro for Qualcomm handhelds (DEVICE=<soc> picks the SoC family)
# See "Building" in CONTRIBUTING.md for the build quick start.
#
# Most targets build an aarch64 Linux image and must run on a Linux host as root
# (chroot/mount). Override config in config/steamling.conf or via the environment.

SHELL   := /bin/bash
SCRIPTS := scripts

.DEFAULT_GOAL := help

.PHONY: help image rootfs update status watch host-setup sync bootstrap build kernel packages seed pending sd-image snapshot base-diff extend-base stage stage-check publish stage-shared stage-check-shared publish-shared publish-image install check mirrors du trim clean distclean

help: ## Show this help
	@echo "steamling build targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

image: ## Everything from host check to flashable SD image, skipping what is current (as yourself; sudo once). SSH=1: SSH on. Same as ./build.sh
	@$(SCRIPTS)/build-all.sh

rootfs: ## make image without the SD image: stops at the finished rootfs in build/rootfs
	@$(SCRIPTS)/build-all.sh --no-sd-image

update: ## Only the kernel and the packages that changed, for updating a handheld over the network (docs/updating.md). Same as ./build.sh --update
	@$(SCRIPTS)/build-all.sh --update

status: ## Where the running (or last) make image is, and its time left
	@$(SCRIPTS)/build-status.sh

watch: ## make status, redrawn every 2 s until the build ends (Ctrl-C stops watching, not the build)
	@$(SCRIPTS)/build-status.sh --watch

host-setup: ## Install this host's build tools and give qemu's binfmt the C flag (Debian/Ubuntu, Fedora, Arch; uses sudo)
	@$(SCRIPTS)/host-setup.sh

sync: ## Fetch ROCKNIX reference material into vendor/ from the pinned commit (STEAMLING_SYNC_SCOPE=all also moves kernel/)
	@$(SCRIPTS)/sync.sh

bootstrap: ## Download + verify + extract the ALARM base rootfs (root, Linux)
	@$(SCRIPTS)/bootstrap.sh

build: ## Image build: bootstrap -> packages -> assemble; needs 'make kernel' first (root, Linux); STEAMLING_EMULATION=1 bakes in the emulation layer
	@$(SCRIPTS)/build-image.sh

kernel: ## Build only the in-project kernel (linux-steamling-<soc>); does nothing if its inputs are unchanged
	@$(SCRIPTS)/build-kernel.sh

packages: ## Build local steamling-* packages -> build/localrepo/{<soc>,shared} (root); skips up-to-date ones. PKG="a b" forces a subset
	@$(SCRIPTS)/build-packages.sh $(PKG)

seed: ## Fill build/localrepo from the published repo, so 'make build' compiles only what differs (root)
	@$(SCRIPTS)/seed-localrepo.sh

pending: ## List the packages 'make build' would compile (missing or stale in build/localrepo)
	@$(SCRIPTS)/pending.sh

sd-image: ## Build a flashable SD boot-test image (needs build + kernel) (root, Linux)
	@$(SCRIPTS)/build-sd-image.sh

snapshot: ## Freeze the ALARM base a fresh build used -> [steamling-base] on GitHub or R2 + lockfile + pins (user, no sudo)
	@$(SCRIPTS)/snapshot-base.sh

base-diff: ## Vet a snapshot dry run: watchlist moves + open upstream issues, fresh upstream bumps (auto after a dry run)
	@$(SCRIPTS)/base-diff.sh

extend-base: ## Host extra ALARM packages in the LIVE base without a re-cut (PKG="samba ..."; deps must already be in it; user, no sudo)
	@$(SCRIPTS)/extend-base.sh $(PKG)

stage: ## Mirror the LIVE repo into build/stage + swap in PKG="a b" (publish source; user, no sudo). DROP="x" removes a live package
	@STEAMLING_STAGE_DROP="$(DROP)" $(SCRIPTS)/stage-repo.sh $(PKG)

stage-check: ## Re-run the consistency gate on the staged repo (runs automatically at the end of 'make stage')
	@$(SCRIPTS)/stage-check.sh

publish: ## Sign + publish the staged repo (run 'make stage' first; user, no sudo)
	@$(SCRIPTS)/publish-repo.sh $(PUBLISH_ARGS)

stage-shared: ## Stage the SoC-neutral [steamling-shared] repo (PKG="a b" [DROP="x"]; once, not per SoC)
	@STEAMLING_REPO_SCOPE=shared STEAMLING_STAGE_DROP="$(DROP)" $(SCRIPTS)/stage-repo.sh $(PKG)

stage-check-shared: ## Re-run the consistency gate on the staged [steamling-shared] repo
	@STEAMLING_REPO_SCOPE=shared $(SCRIPTS)/stage-check.sh

publish-shared: ## Sign + publish the staged [steamling-shared] repo (run 'make stage-shared' first)
	@STEAMLING_REPO_SCOPE=shared $(SCRIPTS)/publish-repo.sh $(PUBLISH_ARGS)

publish-image: ## Compress + checksum + upload the SD image for download
	@$(SCRIPTS)/publish-image.sh

install: ## Point at the on-device internal installer (steamling-install-internal); nothing runs on the host
	@$(SCRIPTS)/install.sh

check: ## Preflight: validate harness + any built artifacts
	@$(SCRIPTS)/check.sh

mirrors: ## Clone or update the upstream reference mirrors in build/mirrors (config/mirrors.list; Windows: scripts/mirrors.ps1)
	@$(SCRIPTS)/mirrors.sh

du: ## Show build/ disk usage breakdown (find the space hogs)
	@du -sh build/* 2>/dev/null | sort -h; \
	 [ -d build/kernel ] && { echo '--- build/kernel ---'; du -sh build/kernel/* 2>/dev/null | sort -h; } || true

trim: ## Reclaim space: drop the regenerable kernel SOURCE trees (keeps KERNEL+modules+rootfs+image)
	@sudo rm -rf build/kernel/*/linux-* build/kernel/*/mkbootimg-src
	@echo "trimmed kernel source tree (re-extracted when 'make kernel' next has something to build); kept out/, rootfs, image, cache"

# rm -rf follows bind mounts, and an interrupted build can leave its chroots' mounts (the host's
# /dev among them) in place, so a clean then deletes the host's device nodes. Refuse instead.
NO_BUILD_MOUNTS = ! findmnt -rno TARGET 2>/dev/null | grep -q '^$(CURDIR)/build/' \
	|| { echo "error: still mounted under $(CURDIR)/build (an interrupted build): reboot, or unmount it, first" >&2; exit 1; }

clean: ## Remove build output: rootfs, image, kernel, package chroots (keeps download cache)
	@$(NO_BUILD_MOUNTS)
	@sudo rm -rf build/rootfs build/image build/localrepo build/built-base build/kernel build/pkgbuild-root*
	@echo "cleaned build artifacts (download cache kept)"

distclean: ## Remove all build output including caches
	@$(NO_BUILD_MOUNTS)
	@sudo rm -rf build/rootfs build/image build/localrepo build/built-base build/kernel build/pkgbuild-root* build/cache
	@echo "removed all build output"
