<#
.SYNOPSIS
  Agent Manager - online installer (Windows / PowerShell). Downloads the release deploy kit, verifies it, and runs the
  installer with sane defaults. Published to the docs site by the `release` workflow, so it is fetched over HTTPS:

    irm https://agentaccessmanager.com/get.ps1 | iex

  With options (a piped script cannot take parameters, so build a scriptblock):

    & ([scriptblock]::Create((irm https://agentaccessmanager.com/get.ps1))) -Url https://aimanager.acme.com

  It asks nothing on the happy path: the public URL defaults to http://<this-computer-name>:8080 and is only accepted
  after the name is confirmed to resolve from this machine (a container cannot use `localhost`, so a resolvable name is
  mandatory). Re-running it upgrades in place: deploy\.env keeps every generated secret and the master key.

  Requires Docker Desktop with the Compose v2 plugin, and tar.exe (bundled with Windows 10 1803+).
#>
[CmdletBinding()]
param(
    [string]$Url,
    [int]$Port = 8080,
    [string]$Channel,
    [string]$Version,
    [string]$Image,
    [string]$License,
    [string]$Dir,
    [switch]$NoOpen
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # the download progress bar is noise in a piped one-liner

$Site = if ($env:AIM_SITE) { $env:AIM_SITE } else { 'https://docs.agentaccessmanager.com' }
$Repo = if ($env:AIM_REPO) { $env:AIM_REPO } else { 'AethosHub/AgentAccessManager' }
if (-not $Dir) { $Dir = if ($env:AIM_HOME) { $env:AIM_HOME } else { Join-Path $env:LOCALAPPDATA 'AIManager' } }
$ReleaseBase = $env:AIM_RELEASE_BASE
# A channel is a directory on the docs site holding its own latest.json + kit, so unreleased builds are installable
# without publishing a GitHub release. The kit comes from there too, not from the releases page.
if ($Channel) {
    $Site = "$Site/$Channel"
    if (-not $ReleaseBase) { $ReleaseBase = $Site }
}

function Say($m)  { Write-Host $m }
function Ok($m)   { Write-Host "  + $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  ! $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host ""; Write-Host "ERROR $m" -ForegroundColor Red; exit 1 }

<#
  Runs a native command and returns its exit code, judging success by that alone.

  Windows PowerShell 5.1 turns a native command's stderr into ErrorRecords, and with $ErrorActionPreference='Stop' those
  are terminating - so anything an exe merely *warns* about kills the script. `docker info` on Docker Desktop routinely
  prints "WARNING: No blkio throttle.read_bps_device support", which aborted this installer before it did anything. The
  preference is relaxed for the duration of the call and restored afterwards.
#>
function Invoke-Native([string]$exe, [string[]]$exeArgs, [switch]$Quiet) {
    $prior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        # Merge stderr in (safe now the preference is relaxed) and write each line with Write-Host: that keeps the
        # command's output in step with our own messages, and keeps the pipeline clean so only the exit code is returned.
        if ($Quiet) { & $exe @exeArgs 2>&1 | Out-Null } else { & $exe @exeArgs 2>&1 | ForEach-Object { Write-Host $_ } }
        return $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $prior }
}

Say ""
Say "Agent Manager installer"
# A redirect set in the environment is invisible otherwise, and `iex` leaves $env:AIM_SITE behind for the rest of the
# session - so a later install here silently used a channel the user never asked for, and failed with a 404 about a
# directory they had never heard of. Say where it is installing from whenever that is not the default.
if ($env:AIM_SITE) { Say "  installing from AIM_SITE=$($env:AIM_SITE) (clear it with `$env:AIM_SITE = `$null)" }
Say ""

# ---- prerequisites -------------------------------------------------------------------------------------------------

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host ""
    Write-Host "ERROR Docker is not installed." -ForegroundColor Red
    Say "  Install Docker Desktop: https://docs.docker.com/desktop/install/windows-install/"
    exit 1
}
if ((Invoke-Native 'docker' @('info') -Quiet) -ne 0) { Die "Docker is installed but not responding - start Docker Desktop and re-run." }
if ((Invoke-Native 'docker' @('compose', 'version') -Quiet) -ne 0) { Die "the Docker Compose v2 plugin is required ('docker compose version' failed)." }
if (-not (Get-Command tar -ErrorAction SilentlyContinue)) { Die "tar.exe not found - it ships with Windows 10 1803+; install it or unpack the kit by hand." }
Ok ((docker --version) -replace ',.*', '')

$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("aim-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $Tmp | Out-Null
try {

    # ---- resolve the release ---------------------------------------------------------------------------------------

    if (-not $Version) {
        try { $latest = Invoke-RestMethod -UseBasicParsing "$Site/latest.json" -TimeoutSec 15 }
        catch { Die "cannot reach $Site/latest.json - pass -Version vX.Y.Z, or check your network." }
        $Version = $latest.version
        if (-not $Version) { Die "no version advertised at $Site/latest.json - pass -Version vX.Y.Z." }
    }
    Ok "Release $Version"

    # Pin the image to the release actually being installed. Without this the installer falls back to the kit's
    # `:latest` default, which makes -Version meaningless and outright fails on a pre-release, where no `latest` tag is
    # published.
    if (-not $Image) { $Image = "ghcr.io/$($Repo.ToLower()):$Version" }

    $kit  = "aimanager-$Version-deploy.tar.gz"
    $base = if ($ReleaseBase) { $ReleaseBase } else { "https://github.com/$Repo/releases/download/$Version" }
    $kitPath = Join-Path $Tmp $kit
    try { Invoke-WebRequest -UseBasicParsing "$base/$kit" -OutFile $kitPath }
    catch { Die "could not download $base/$kit - is $Version a published release?" }

    # The release always ships SHA256SUMS beside the kit; a missing one is worth a warning but not a stop.
    $sumsPath = Join-Path $Tmp 'SHA256SUMS'
    $haveSums = $true
    try { Invoke-WebRequest -UseBasicParsing "$base/SHA256SUMS" -OutFile $sumsPath } catch { $haveSums = $false }
    if ($haveSums) {
        $expected = $null
        foreach ($line in Get-Content $sumsPath) {
            $parts = $line -split '\s+' | Where-Object { $_ }
            if ($parts.Count -ge 2 -and ($parts[1] -eq $kit -or $parts[1] -eq "*$kit")) { $expected = $parts[0]; break }
        }
        $actual = (Get-FileHash -Algorithm SHA256 $kitPath).Hash.ToLower()
        if (-not $expected) { Warn "SHA256SUMS has no entry for $kit - skipping verification." }
        elseif ($expected.ToLower() -ne $actual) { Die "checksum mismatch for $kit - refusing to install. Expected $expected, got $actual." }
        else { Ok "Downloaded $kit, checksum verified" }
    }
    else { Warn "no SHA256SUMS published for $Version - skipping verification." }

    # ---- unpack ----------------------------------------------------------------------------------------------------

    # The kit archives everything under a top-level `aimanager/`, so strip it. An existing install is overwritten except
    # deploy\.env, which the kit does not contain - so secrets survive an upgrade.
    if (-not (Test-Path $Dir)) { New-Item -ItemType Directory -Path $Dir | Out-Null }
    if ((Invoke-Native 'tar' @('-xzf', $kitPath, '-C', $Dir, '--strip-components=1')) -ne 0) {
        Die "could not unpack $kit into $Dir."
    }
    if (-not (Test-Path (Join-Path $Dir 'aimanager.ps1'))) { Die "$Dir\aimanager.ps1 missing after unpack - the kit layout is not what was expected." }
    Ok "Installed to $Dir"

    # ---- choose the URL --------------------------------------------------------------------------------------------

    function Test-Resolves($name) {
        try { [System.Net.Dns]::GetHostEntry($name) | Out-Null; return $true } catch { return $false }
    }
    function Test-PortBusy($p) {
        try { return @(Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue).Count -gt 0 }
        catch { return $false }   # unknown means "assume free"; this only picks a friendlier default
    }

    if (-not $Url) {
        $name = $env:COMPUTERNAME
        if (-not $name -or $name -eq 'localhost') {
            Die "this machine's name is '$name', which a container resolves to itself.`n  Pass a name that resolves here, e.g. -Url http://myhost:$Port"
        }
        if (-not (Test-Resolves $name)) {
            Die @"
'$name' is this machine's name but does not resolve from here, so the browser could not reach it.
  Fix it with either:
    1. add it to your hosts file (as Administrator):
       Add-Content `$env:WINDIR\System32\drivers\etc\hosts "127.0.0.1 $name"
    2. or pass a name that resolves: -Url http://<name-or-dns>:$Port
  (Note: 'localhost' cannot be used - a container resolves it to itself, so the app could not reach its bundled IdP.)
"@
        }
        # Only auto-shift the port when the caller did not pin one, so an explicit -Port is never silently ignored.
        if (-not $PSBoundParameters.ContainsKey('Port') -and (Test-PortBusy $Port)) {
            $free = @(8081, 8082, 8083, 8090, 9080) | Where-Object { -not (Test-PortBusy $_) } | Select-Object -First 1
            if (-not $free) { Die "port $Port is in use and no fallback port was free - pass -Port N." }
            Warn "Port $Port is in use - using $free instead"
            $Port = $free
        }
        $Url = "http://${name}:$Port"
        Ok "Computer name '$name' resolves - serving at $Url"
    }
    else { Ok "Serving at $Url (as requested)" }

    # ---- hand off to the control script ----------------------------------------------------------------------------

    Say ""
    # Named parameters MUST go through a hashtable splat. An array splat passes its elements POSITIONALLY, so
    # @('install','-Yes','-Url',$url) binds 'install' to $Command, '-Yes' to $Arg, and then has nowhere to put '-Url' -
    # failing with "a positional parameter cannot be found that accepts argument '-Url'".
    $named = @{ Yes = $true; Url = $Url }
    if ($Image)   { $named.Image = $Image }
    if ($License) { $named.License = $License }
    & (Join-Path $Dir 'aimanager.ps1') 'install' @named
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    # ---- open a browser --------------------------------------------------------------------------------------------

    if (-not $NoOpen) {
        $target = "$Url/dashboard"
        Say "Opening $target ..."
        try { Start-Process $target } catch { }
    }
}
finally {
    Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
}
