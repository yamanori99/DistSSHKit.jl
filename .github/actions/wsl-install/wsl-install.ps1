# Register a WSL distribution, then exit.
#
# A stuck wsl.exe keeps the step's stdout and stderr open. The GitHub runner
# waits for those pipes, so timeout-minutes on the step does not reap it.
# The deadline has to be in the process that starts wsl.exe, and wsl.exe must
# not inherit this step's pipes. Output goes to files. On the deadline this
# process kills that process tree and then exits.
#
# What already shipped, and what it left inside Vampire/setup-wsl:
#
# - DistSSHRun #43 and DistSSHKit #457 put timeout-minutes: 10 on the action.
#   The intent was that a hung `wsl --install` would fail at 10 minutes instead
#   of the 45 minute job limit. It does not. The wsl.exe from that step keeps
#   the pipes.
#   https://github.com/yamanori99/DistSSHRun.jl/pull/43
#   https://github.com/yamanori99/DistSSHKit.jl/pull/457
# - DistSSHRun #96 and DistSSHKit #488 recorded that fact and moved
#   `apt-get install` of curl and git out of the action into wsl-julia.sh,
#   under `timeout 180`. Weekly SSH E2E still passed additional-packages, so
#   apt-get stayed inside the action there.
#   https://github.com/yamanori99/DistSSHRun.jl/pull/96
#   https://github.com/yamanori99/DistSSHKit.jl/pull/488
# - DistSSHRun #134 and DistSSHQueue #407 moved that remaining apt-get into
#   wsl-apt.sh, again under `timeout 180`. `wsl --install --from-file` stayed
#   inside the action. That is the command that does not return.
#   https://github.com/yamanori99/DistSSHRun.jl/pull/134
#   https://github.com/yamanori99/DistSSHQueue.jl/pull/407
#
# On DistSSHRun #135 (2026-10-20) the Pkg.test WSL job and the DistSSHUp WSL
# job stopped in setup-wsl after the rootfs cache restore, at
# `wsl.exe --install --from-file ... --no-launch`. The 10 minute step limit
# did not end them. DistSSHBase's WSL job in the same run got past that
# command. This script is that install, moved out. Do not put it back in the
# action, and do not treat another timeout-minutes as the fix.
#
# setup-wsl skips Install Distribution once `wsl --distribution <id> true`
# exits 0. v7.2.0 (4c48163) and v7.0.0 (d1da7f2) both do this. After this
# script's probe succeeds, the action does not run `--install` again. It
# still runs short `wsl` probes while writing the wsl-bash wrapper. Those
# are not this hang.
# https://github.com/Vampire/setup-wsl/blob/4c48163d9f981914dd8caa0fc335fe19cca5bff4/src/jsMain/kotlin/net/kautler/github/action/setup_wsl/SetupWsl.kt
# https://github.com/Vampire/setup-wsl/blob/d1da7f2c0322a5ee4f24975344f67fc0f5baf364/src/jsMain/kotlin/net/kautler/github/action/setup_wsl/SetupWsl.kt
#
# This repository pins setup-wsl v7.0.0. The rootfs URL is the Ubuntu-24.04
# file that pin installs (24.04.4). The same step in DistSSHRun is #136, which
# uses 24.04.5 because that repository pins v7.2.0. The distribution name has
# to match the setup-wsl `distribution` input that follows.
# https://github.com/yamanori99/DistSSHRun.jl/pull/136
$ErrorActionPreference = "Stop"

$Name = $env:WSL_INSTALL_NAME
$Url = $env:WSL_INSTALL_URL
$Seconds = [int]$env:WSL_INSTALL_SECONDS
if ([string]::IsNullOrWhiteSpace($Name)) { $Name = "Ubuntu-24.04" }
if ([string]::IsNullOrWhiteSpace($Url)) {
    $Url = "https://releases.ubuntu.com/24.04.4/ubuntu-24.04.4-wsl-amd64.wsl"
}
if ($Seconds -lt 1) { $Seconds = 180 }

$Wsl = Join-Path $env:SystemRoot "System32\wsl.exe"
$Taskkill = Join-Path $env:SystemRoot "System32\taskkill.exe"
$Temp = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { $env:TEMP }

function Invoke-Wsl {
    param(
        [Parameter(Mandatory = $true)][string[]]$WslArgs,
        [Parameter(Mandatory = $true)][int]$Limit
    )
    $stamp = [guid]::NewGuid().ToString("n")
    $out = Join-Path $Temp "wsl-$stamp.out"
    $err = Join-Path $Temp "wsl-$stamp.err"
    $proc = Start-Process -FilePath $Wsl -ArgumentList $WslArgs -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput $out -RedirectStandardError $err
    $finished = $proc.WaitForExit($Limit * 1000)
    if (-not $finished) {
        & $Taskkill /F /T /PID $proc.Id | Out-Host
        $null = $proc.WaitForExit(10000)
    }
    foreach ($path in @($out, $err)) {
        if (Test-Path $path) { Get-Content $path | Write-Host }
    }
    if (-not $finished) { return 124 }
    return $proc.ExitCode
}

$probe = Invoke-Wsl -WslArgs @("--distribution", $Name, "--", "true") -Limit 30
if ($probe -eq 0) {
    Write-Host "$Name is already registered"
    exit 0
}

# About 370MB. --retry starts again at byte 0, so a slow link spends every
# attempt and still has no file. Each attempt keeps the bytes it received.
# Two attempts that add nothing fail only while the file is still empty.
# After any bytes are kept, only the twenty minute budget stops the download.
# $Seconds still bounds wsl.exe.
$dest = Join-Path $Temp "wsl-install.wsl"
$downloadStart = Get-Date
$stalls = 0
while ($true) {
    if (((Get-Date) - $downloadStart).TotalMinutes -ge 20) {
        Write-Host "rootfs download exceeded 20 minutes"
        exit 1
    }
    $before = 0L
    if (Test-Path $dest) { $before = (Get-Item $dest).Length }
    & curl.exe --fail --location --continue-at - --connect-timeout 20 --max-time 180 -o $dest $Url
    $code = $LASTEXITCODE
    $after = 0L
    if (Test-Path $dest) { $after = (Get-Item $dest).Length }
    if ($code -eq 0) { break }
    if ($after -gt $before) {
        $stalls = 0
        Write-Host "rootfs download kept $after bytes (curl $code)"
        continue
    }
    $stalls += 1
    Write-Host "rootfs download added no bytes ($stalls, curl $code)"
    if ($before -eq 0 -and $stalls -ge 2) { exit $code }
}

foreach ($attempt in 1, 2) {
    $install = Invoke-Wsl -WslArgs @(
        "--install", "--from-file", $dest, "--no-launch", "--name", $Name
    ) -Limit $Seconds
    $probe = Invoke-Wsl -WslArgs @("--distribution", $Name, "--", "true") -Limit 30
    if ($probe -eq 0) {
        Write-Host "$Name registered"
        exit 0
    }
    Write-Host "register attempt $attempt failed (install $install, probe $probe)"
}

exit 1
