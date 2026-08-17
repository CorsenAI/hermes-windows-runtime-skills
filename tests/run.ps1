[CmdletBinding()]
param(
    [string]$PythonExe = $env:HERMES_TEST_PYTHON,
    [switch]$SkipGitBash,
    [string]$WslDistro,
    [string]$WslPythonSeries
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($PythonExe)) {
    throw 'Pass -PythonExe with an already-verified interpreter path; no PATH fallback is allowed.'
}
if (-not [string]::IsNullOrWhiteSpace($WslDistro) -and $WslPythonSeries -notmatch '^\d+\.\d+$') {
    throw 'Pass -WslPythonSeries as an exact major.minor when using -WslDistro.'
}

$PythonExe = [IO.Path]::GetFullPath($PythonExe)
$pythonItem = Get-Item -LiteralPath $PythonExe -ErrorAction Stop
if ($pythonItem.PSIsContainer -or ($pythonItem.Length -eq 0 -and
        -not ($pythonItem.Attributes -band [IO.FileAttributes]::ReparsePoint))) {
    throw 'The test interpreter must be an executable file or verified reparse alias.'
}
& $PythonExe -I -S -B -c 'import sys; raise SystemExit(0 if sys.executable else 2)'
if ($LASTEXITCODE -ne 0) { throw 'The explicit test interpreter failed its identity probe.' }

function Invoke-Checked {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][scriptblock]$Action
    )

    & $Action
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed with exit code $LASTEXITCODE."
    }
}

Invoke-Checked 'YAML/frontmatter validation' {
    & $PythonExe -I -B (Join-Path $PSScriptRoot 'validate_frontmatter.py') $repoRoot
}

Invoke-Checked 'Static contract validation' {
    & (Join-Path $PSScriptRoot 'static.ps1') -RepoRoot $repoRoot
}

if ($env:OS -eq 'Windows_NT') {
    Invoke-Checked 'Windows runtime contracts' {
        & (Join-Path $PSScriptRoot 'windows.ps1') -RepoRoot $repoRoot -PythonExe $PythonExe
    }

    if (-not $SkipGitBash) {
        $bashCandidates = @(@(
            (Join-Path $env:ProgramFiles 'Git/bin/bash.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'Git/bin/bash.exe'),
            (Join-Path $env:LOCALAPPDATA 'Programs/Git/bin/bash.exe')
        ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) })

        if ($bashCandidates.Count -eq 0) {
            throw 'Git Bash is required for the Windows validation matrix.'
        }

        $bashExe = [IO.Path]::GetFullPath($bashCandidates[0])
        $bashScript = & $bashExe --noprofile --norc -c '/usr/bin/cygpath.exe -u "$1"' _ (Join-Path $PSScriptRoot 'git-bash.sh')
        if ($LASTEXITCODE -ne 0 -or -not $bashScript) {
            throw 'Could not convert the Git Bash test path.'
        }

        $oldWslDistro = $env:HERMES_TEST_WSL_DISTRO
        $oldWslSeries = $env:HERMES_TEST_WSL_PYTHON_SERIES
        try {
            if (-not [string]::IsNullOrWhiteSpace($WslDistro)) {
                $env:HERMES_TEST_WSL_DISTRO = $WslDistro
                $env:HERMES_TEST_WSL_PYTHON_SERIES = $WslPythonSeries
            }
            Invoke-Checked 'Git Bash argument-routing contracts' {
                & $bashExe --noprofile --norc $bashScript
            }
        }
        finally {
            if ($null -eq $oldWslDistro) { Remove-Item Env:HERMES_TEST_WSL_DISTRO -ErrorAction SilentlyContinue } else { $env:HERMES_TEST_WSL_DISTRO = $oldWslDistro }
            if ($null -eq $oldWslSeries) { Remove-Item Env:HERMES_TEST_WSL_PYTHON_SERIES -ErrorAction SilentlyContinue } else { $env:HERMES_TEST_WSL_PYTHON_SERIES = $oldWslSeries }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($WslDistro)) {
        Invoke-Checked 'Live WSL contracts' {
            & (Join-Path $PSScriptRoot 'wsl-live.ps1') -Distro $WslDistro -PythonSeries $WslPythonSeries
        }
    }
}
else {
    Invoke-Checked 'Linux backend contracts' {
        & /usr/bin/bash (Join-Path $PSScriptRoot 'linux-backend.sh')
    }
}

Write-Output 'PASS: production validation suite completed.'
