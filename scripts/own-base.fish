#!/usr/bin/env fish
# own-base.fish - cut Steamling's own frozen Arch Linux ARM base on an Arch or CachyOS x86_64 host,
# so builds and devices stop borrowing Pocknix's. docs/building/own-base.md explains each step;
# this runs them.
#
#   scripts/own-base.fish [--github <owner/repo>] [--remote <rclone destination>] [--url <public url>]
#                         [--id <label>] [--yes]
# --github hosts the base on that repo's releases (the URL follows from it); --remote and --url
# host it on rclone storage instead. With no flags it takes STEAMLING_BASE_GITHUB, or
# STEAMLING_BASE_RCLONE_REMOTE and STEAMLING_BASE_URL, from config/local.conf (copy
# config/local.conf.example to start one), so a filled-in local.conf makes this a single
# command. The flags win over the file.
#
# It points config/steamling.conf at your base and unpins it, builds everything against live Arch
# Linux ARM, freezes exactly what that build installed with `make snapshot` (which uploads it and
# pins the config again), checks the URL serves it, then builds once more against the frozen base.
# Afterwards, commit config/steamling.conf and the new steamling-base.lock.

set -l root (path resolve (status dirname)/..)
cd $root; or exit 1

function step
    set_color --bold cyan; echo "==> $argv"; set_color normal
end
function fail
    set_color red; echo "error: $argv" >&2; set_color normal; exit 1
end

argparse 'github=' 'remote=' 'url=' 'id=' y/yes h/help -- $argv; or exit 2
if set -q _flag_help
    sed -n '6,12p' (status filename)
    exit 0
end
# config/local.conf is bash, so let bash read it
function local_conf -a name
    test -f config/local.conf; or return
    bash -c 'source config/local.conf >/dev/null 2>&1; printf "%s" "${!1}"' sh $name
end
set -l github (local_conf STEAMLING_BASE_GITHUB)
set -l remote (local_conf STEAMLING_BASE_RCLONE_REMOTE)
set -l url (local_conf STEAMLING_BASE_URL)
set -q _flag_github; and set github $_flag_github
set -q _flag_remote; and set remote $_flag_remote
set -q _flag_url; and set url $_flag_url
# GitHub: the URL is the repo's release download address unless one was given that already is
if test -n "$github"
    string match -q "https://github.com/$github/releases/download/*" -- $url
    or set url https://github.com/$github/releases/download/base
    set remote ""
end
test -n "$github"; or begin; test -n "$remote"; and test -n "$url"; end
or fail "no base storage set: fill in config/local.conf (cp config/local.conf.example config/local.conf), or pass --github, or --remote and --url"
string match -q '*REPLACE-ME*' -- $url
and fail "config/local.conf still has the example address: put your bucket's public URL in STEAMLING_BASE_URL"
set url (string trim --right --chars / -- $url)
set -l id (date -u +%Y%m%d)
set -q _flag_id; and set id $_flag_id
set -l conf config/steamling.conf

step "checking the host"
set -l uploader rclone
test -n "$github"; and set uploader github-cli
for t in git make (string replace github-cli gh -- $uploader) repo-add curl sudo
    command -q $t; or fail "$t is missing: sudo pacman -S --needed git make $uploader pacman curl sudo"
end
switch (uname -m)
    case x86_64
        test -e /proc/sys/fs/binfmt_misc/qemu-aarch64
        or fail "aarch64 programs can't run here yet: sudo pacman -S --needed qemu-user-static qemu-user-static-binfmt, then reboot (docs/building/linux-host.md)"
    case aarch64
    case '*'
        fail "this needs an x86_64 or aarch64 host, not "(uname -m)
end
command -q ccache; or echo "note: no ccache on this host, so kernel rebuilds start from scratch (sudo pacman -S ccache)"
# A rerun finds the config already pointing here (the first run did that), so only a fresh run
# insists on a clean config.
if not grep -q "STEAMLING_BASE_URL:=$url}" $conf
    git diff --quiet -- $conf packages/shared/steamling-base-lock
    or fail "$conf or the base lock has uncommitted changes; commit or stash them first"
end
if test -n "$github"
    gh auth status >/dev/null 2>&1; or fail "gh isn't logged in: run gh auth login"
    gh repo view $github >/dev/null 2>&1
    or fail "gh can't see $github: create it on GitHub first (tick 'Add a README' so it has a commit)"
else
    rclone lsf --max-depth 1 $remote >/dev/null 2>&1; or rclone mkdir $remote
    or fail "rclone can't reach $remote (set the remote up with: rclone config)"
end

echo
echo "  base label:   $id"
if test -n "$github"
    echo "  uploads to:   releases of github.com/$github"
else
    echo "  uploads to:   $remote"
end
echo "  served from:  $url"
echo "  This builds everything twice. Under qemu that takes hours, mostly the first time."
if not set -q _flag_yes
    read -l -P "  Go on? [y/N] " answer
    string match -qi y -- $answer; or exit 1
end

# Every build names its base outright: config/local.conf may say STEAMLING_BASE_SNAPSHOT=live or
# hold other storage, and the command line beats it.
set -l base STEAMLING_BASE_URL=$url STEAMLING_BASE_RCLONE_REMOTE=$remote STEAMLING_BASE_GITHUB=$github

step "pointing $conf at your storage"
# the rclone remote line keeps its default when the base goes to GitHub
set -l edits -e "s|^: \"\${STEAMLING_BASE_URL:=.*}\"|: \"\${STEAMLING_BASE_URL:=$url}\"|" \
    -e "s|^: \"\${STEAMLING_BASE_GITHUB:=.*}\"|: \"\${STEAMLING_BASE_GITHUB:=$github}\"|"
test -n "$remote"
and set -a edits -e "s|^: \"\${STEAMLING_BASE_RCLONE_REMOTE:=.*}\"|: \"\${STEAMLING_BASE_RCLONE_REMOTE:=$remote}\"|"
sed -i $edits $conf
grep -q "STEAMLING_BASE_URL:=$url}" $conf; or fail "couldn't point $conf at $url"

if grep -q "STEAMLING_BASE_SNAPSHOT:=$id}" $conf
    step "base $id is already cut (an earlier run got that far); going on to the check"
else
    step "building against live Arch Linux ARM (make image)"
    env $base STEAMLING_BASE_SNAPSHOT=live make image
    or fail "the live build failed; fix it and run this again (it picks up where it stopped)"

    step "freezing that build as base $id (make snapshot)"
    env $base STEAMLING_BASE_SNAPSHOT=live STEAMLING_SNAPSHOT_ID=$id make snapshot
    or fail "make snapshot failed; fix it and run this again"
end

step "checking $url serves the new base"
curl -fsIL $url/steamling-base.db >/dev/null
or fail "$url/steamling-base.db isn't reachable. Make the bucket or repo public (or put a domain in front of the bucket), then run this again"

step "building against the frozen base (make image)"
env $base STEAMLING_BASE_SNAPSHOT=$id make image
or fail "the build against the frozen base failed; fix it and run this again"

echo
step "done: base $id is live at $url"
echo "  Next: git add $conf packages/shared/steamling-base-lock/steamling-base.lock"
echo "        git commit -m \"base: our own snapshot $id\""
echo "  Handhelds move onto it the next time you update them from this build (docs/updating.md)."
string match -q live -- (local_conf STEAMLING_BASE_SNAPSHOT)
and echo "  config/local.conf still says STEAMLING_BASE_SNAPSHOT=live: delete that line, or later builds skip your base."
