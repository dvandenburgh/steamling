# mirrors.ps1 - scripts/mirrors.sh for a Windows checkout: clone what config/mirrors.list names
# into build\mirrors as bare repos, and fetch the ones already there; `file` entries are downloaded. Branches and tags only.
# Safe to re-run. $env:STEAMLING_MIRRORS_DIR moves them.
#   powershell -ExecutionPolicy Bypass -File scripts\mirrors.ps1
git config --global core.longpaths true
$Root = Split-Path -Parent $PSScriptRoot
$M = if ($env:STEAMLING_MIRRORS_DIR) { $env:STEAMLING_MIRRORS_DIR } else { Join-Path $Root 'build\mirrors' }
New-Item -ItemType Directory -Force $M | Out-Null
$failed = $false

foreach ($line in Get-Content (Join-Path $Root 'config\mirrors.list')) {
    $line = $line.Trim()
    if ($line -eq '' -or $line.StartsWith('#')) { continue }
    $f = $line -split '\s+'
    $name = $f[0]; $url = $f[1]; $clone = $f[2]
    $branches = if ($f.Count -gt 3) { $f[3] } else { '*' }
    # A plain file (a package database, an index page): downloaded fresh each run.
    if ($clone -eq 'file') {
        $out = Join-Path $M $name
        New-Item -ItemType Directory -Force (Split-Path -Parent $out) | Out-Null
        Write-Host "==> fetching $name"
        try { Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $out }
        catch { Write-Warning "fetch failed: $name"; $failed = $true }
        continue
    }
    switch ($clone) {
        'full'     { $cloneArgs = @() }
        'shallow'  { $cloneArgs = @('--depth', '1') }
        'blobless' { $cloneArgs = @('--filter=blob:none') }
        default    { Write-Warning "${name}: unknown clone mode '$clone'"; $failed = $true; continue }
    }
    $repo = ($name -split ':')[0]
    $dir = Join-Path $M $repo
    $fetchArgs = @()
    if ($repo -eq $name) {
        $remote = 'origin'
        if (-not (Test-Path $dir)) {
            Write-Host "==> cloning $repo"
            git clone --bare @cloneArgs $url $dir
            if ($LASTEXITCODE -ne 0) { Write-Warning "clone failed: $repo"; $failed = $true; continue }
        }
        git -C $dir config remote.origin.fetch '+refs/heads/*:refs/heads/*'
    } else {
        $remote = ($name -split ':', 2)[1]
        if (-not (Test-Path $dir)) { Write-Warning "${name}: $repo is not cloned"; $failed = $true; continue }
        if (-not (git -C $dir remote | Select-String -Quiet "^$remote$")) { git -C $dir remote add $remote $url }
        git -C $dir config "remote.$remote.fetch" "+refs/heads/${branches}:refs/heads/$remote/${branches}"
        if ($clone -ne 'shallow') { $fetchArgs = $cloneArgs }
    }
    Write-Host "==> fetching $name"
    git -C $dir fetch --prune --tags @fetchArgs $remote
    if ($LASTEXITCODE -ne 0) { Write-Warning "fetch failed: $name"; $failed = $true }
}

Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK' | Set-Content (Join-Path $M 'LAST_FETCH')
Write-Host "done: $M"
if ($failed) { exit 1 }
