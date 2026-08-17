[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Distro,
    [Parameter(Mandatory)][ValidatePattern('^\d+\.\d+$')][string]$PythonSeries
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($env:OS -ne 'Windows_NT') { throw 'This test must run on native Windows.' }
if ([string]::IsNullOrWhiteSpace($Distro)) { throw 'An explicit WSL distribution is required.' }

$wslPath = [IO.Path]::Combine([Environment]::SystemDirectory, 'wsl.exe')
$wslFile = [IO.FileInfo]::new($wslPath); $wslFile.Refresh()
if (-not $wslFile.Exists -or $wslFile.Length -le 0 -or
    ($wslFile.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw 'The fixed system wsl.exe is not a regular file.'
}
$wslApp = $ExecutionContext.InvokeCommand.GetCommand(
    $wslPath, [System.Management.Automation.CommandTypes]::Application
)
if ($null -eq $wslApp -or
    -not $wslApp.Path.Equals($wslPath, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The fixed system wsl.exe is not invokable as an application.'
}
$oldWslEnv = [Environment]::GetEnvironmentVariable('WSLENV', 'Process')
$oldLdPreload = [Environment]::GetEnvironmentVariable('LD_PRELOAD', 'Process')

if ('0:4755' -match '^0:(?<mode>[0-7]{3})$') {
    throw 'The WSL ownership contract accepted a setuid mode.'
}

try {
    [Environment]::SetEnvironmentVariable('LD_PRELOAD', '/definitely/not/present/release-gate.so', 'Process')
    [Environment]::SetEnvironmentVariable('WSLENV', '', 'Process')

$repoRoot = Split-Path -Parent $PSScriptRoot
$before = @(& $wslApp --list --quiet | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
if ($LASTEXITCODE -ne 0 -or $before -notcontains $Distro) {
    throw 'The requested WSL distribution is not already installed.'
}

$windowsRoot = $repoRoot.Replace('\', '/')
$wslRoot = & $wslApp -d $Distro --exec /usr/bin/wslpath -u $windowsRoot
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($wslRoot)) {
    throw 'Could not map the repository into the selected WSL distribution.'
}
$wslRoot = "$wslRoot".Trim()

& $wslApp -d $Distro --exec /usr/bin/bash "$wslRoot/tests/linux-backend.sh" --expect-wsl
if ($LASTEXITCODE -ne 0) { throw 'WSL backend contract failed.' }

$forwardedPreload = @(& $wslApp -d $Distro --exec /usr/bin/printenv LD_PRELOAD)
if ($LASTEXITCODE -ne 1 -or $forwardedPreload.Count -ne 0) {
    throw 'Clearing WSLENV did not block Windows-side LD_PRELOAD propagation.'
}

$runtimeName = "python$PythonSeries"
$resolved = [System.Collections.Generic.List[string]]::new()
foreach ($candidate in @("/usr/bin/$runtimeName", "/usr/local/bin/$runtimeName")) {
    & $wslApp -d $Distro --exec /usr/bin/test -e $candidate
    if ($LASTEXITCODE -eq 1) { continue }
    if ($LASTEXITCODE -ne 0) { throw 'WSL candidate existence check failed.' }
    $canonical = @(& $wslApp -d $Distro --exec /usr/bin/readlink -f -- $candidate)
    if ($LASTEXITCODE -ne 0 -or $canonical.Count -ne 1 -or $canonical[0] -notmatch '^/[A-Za-z0-9._/+:-]+$') {
        throw 'WSL candidate canonicalization failed.'
    }
    & $wslApp -d $Distro --exec /usr/bin/test -x $canonical[0]
    if ($LASTEXITCODE -ne 0) { throw 'WSL candidate is not executable.' }
    & $wslApp -d $Distro --exec /usr/bin/test -f $canonical[0]
    if ($LASTEXITCODE -ne 0) { throw 'WSL candidate is not a regular file.' }
    $metadata = @(& $wslApp -d $Distro --exec /usr/bin/stat -c '%u:%a' -- $canonical[0])
    if ($LASTEXITCODE -ne 0 -or $metadata.Count -ne 1 -or $metadata[0] -notmatch '^0:(?<mode>[0-7]{3})$') {
        throw 'WSL candidate ownership/mode check failed.'
    }
    $mode = $Matches['mode']
    if ($mode.Substring($mode.Length - 2) -match '[2367]') { throw 'WSL candidate is group/other writable.' }
    if (-not $resolved.Contains($canonical[0])) { $resolved.Add($canonical[0]) }
}
if ($resolved.Count -ne 1) { throw 'The exact WSL runtime resolution was absent or ambiguous.' }
$pythonPath = $resolved[0]
& $wslApp -d $Distro --exec /usr/bin/test '!' -e "${pythonPath}._pth"
if ($LASTEXITCODE -ne 0) { throw 'A WSL ._pth startup override was present.' }
$identityCode = "import sys; print(sys.executable); print('%d.%d.%d' % sys.version_info[:3])"
$identity = @(& $wslApp -d $Distro --exec /usr/bin/env PYTHONEXECUTABLE=/tmp/foreign-python __PYVENV_LAUNCHER__=/tmp/foreign-venv /usr/bin/env -u PYTHONEXECUTABLE -u __PYVENV_LAUNCHER__ $pythonPath -I -S -B -c $identityCode)
$identityExit = $LASTEXITCODE
if ($identityExit -ne 0 -or $identity.Count -ne 2 -or $identity[0] -ne $pythonPath -or
    $identity[1] -notmatch ('^' + [regex]::Escape($PythonSeries) + '\.\d+$')) {
    throw 'The exact WSL runtime identity did not match the requested series.'
}

$after = @(& $wslApp --list --quiet | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
if ($LASTEXITCODE -ne 0 -or (Compare-Object $before $after)) {
    throw 'The WSL distribution inventory changed during a read-only test.'
}

Write-Output "PASS: WSL live release gate completed for $Distro with Python $PythonSeries."
}
finally {
    $restoreWslEnv = if ($null -eq $oldWslEnv) { [System.Management.Automation.Language.NullString]::Value } else { $oldWslEnv }
    $restoreLdPreload = if ($null -eq $oldLdPreload) { [System.Management.Automation.Language.NullString]::Value } else { $oldLdPreload }
    [Environment]::SetEnvironmentVariable('WSLENV', $restoreWslEnv, 'Process')
    [Environment]::SetEnvironmentVariable('LD_PRELOAD', $restoreLdPreload, 'Process')
}
