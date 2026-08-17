[CmdletBinding()]
param([Parameter(Mandatory)][string]$RepoRoot)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($env:OS -ne 'Windows_NT') { throw 'The pinned scanner asset in this script targets Windows x64.' }

$version = '8.30.1'
$expectedSha256 = 'd29144deff3a68aa93ced33dddf84b7fdc26070add4aa0f4513094c8332afc4e'
$asset = "gitleaks_${version}_windows_x64.zip"
$url = "https://github.com/gitleaks/gitleaks/releases/download/v$version/$asset"
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("hermes-gitleaks-{0}" -f [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot | Out-Null

try {
    $archive = Join-Path $tempRoot $asset
    Invoke-WebRequest -Uri $url -OutFile $archive -UseBasicParsing
    $actual = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expectedSha256) { throw 'Gitleaks archive checksum mismatch.' }
    Expand-Archive -LiteralPath $archive -DestinationPath $tempRoot
    $scanner = Join-Path $tempRoot 'gitleaks.exe'
    if (-not (Test-Path -LiteralPath $scanner -PathType Leaf)) { throw 'Gitleaks executable missing from verified archive.' }

    $canaryDir = Join-Path $tempRoot 'canary'
    New-Item -ItemType Directory -Path $canaryDir | Out-Null
    $alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'.ToCharArray()
    $random = [Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = New-Object byte[] 82
    $random.GetBytes($bytes)
    $suffix = -join ($bytes | ForEach-Object { $alphabet[$_ % $alphabet.Length] })
    [IO.File]::WriteAllText((Join-Path $canaryDir 'probe.txt'), (('github' + '_pat_') + $suffix))
    & $scanner dir --redact --no-banner $canaryDir
    $canaryExit = $LASTEXITCODE
    Remove-Item -LiteralPath $canaryDir -Recurse -Force
    if ($canaryExit -ne 1) { throw "Gitleaks canary was not detected (exit $canaryExit); refusing a false-negative scan." }

    $source = [IO.Path]::GetFullPath($RepoRoot)
    & $scanner dir --redact --no-banner $source
    if ($LASTEXITCODE -ne 0) { throw "Gitleaks working-tree scan failed with exit code $LASTEXITCODE." }
    & $scanner git --log-opts='--all' --redact --no-banner $source
    if ($LASTEXITCODE -ne 0) { throw "Gitleaks history scan failed with exit code $LASTEXITCODE." }

    $history = @(& git -C $source log --all --format=fuller --patch --no-ext-diff --no-renames)
    if ($LASTEXITCODE -ne 0) { throw 'Could not inspect repository history for publication metadata.' }
    $historyText = $history -join "`n"
    $profilePattern = '(?i)(?:[A-Z]:[\\/]|/[a-z]/|/mnt/[a-z]/)Users[\\/][A-Za-z0-9][A-Za-z0-9._-]*(?:[\\/]|$)'
    $coAuthorPattern = '(?im)^Co-authored-by:\s*\S'
    if ([regex]::IsMatch($historyText, $profilePattern)) { throw 'A personal profile path exists in repository history.' }
    if ([regex]::IsMatch($historyText, $coAuthorPattern)) { throw 'An unexpected co-author trailer exists in repository history.' }

    Write-Output "PASS: Gitleaks $version self-test passed; working tree and full history contain no detected secrets or local profile paths."
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
