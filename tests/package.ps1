[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$OutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
if (Test-Path -LiteralPath $OutputPath) { throw 'Refusing to overwrite an existing archive.' }

$status = & git -C $RepoRoot status --porcelain=v1
if ($LASTEXITCODE -ne 0) { throw 'Repository status check failed.' }
if ($status) { throw 'Repository must be clean before packaging HEAD.' }

$versions = @(Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'skills') -Filter SKILL.md -Recurse | ForEach-Object {
    $match = [regex]::Match((Get-Content -LiteralPath $_.FullName -Raw), '(?m)^version: (?<value>\S+)$')
    if (-not $match.Success) { throw "Missing version in $($_.FullName)" }
    $match.Groups['value'].Value
} | Sort-Object -Unique)
if ($versions.Count -ne 1) { throw 'All skills must share one release version.' }
$expectedName = "hermes-windows-runtime-skills-v$($versions[0]).zip"
if ([IO.Path]::GetFileName($OutputPath) -ne $expectedName) {
    throw "Archive name must be $expectedName."
}

try {
    $prefix = "hermes-windows-runtime-skills-v$($versions[0])/"
    & git -C $RepoRoot archive --format=zip "--prefix=$prefix" "--output=$OutputPath" HEAD
    if ($LASTEXITCODE -ne 0) { throw 'git archive failed.' }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($OutputPath)
    try {
        $entries = @($zip.Entries | Where-Object { -not $_.FullName.EndsWith('/') } | ForEach-Object { $_.FullName })
        foreach ($entry in $entries) {
            if (-not $entry.StartsWith($prefix, [StringComparison]::Ordinal)) { throw "Archive prefix mismatch: $entry" }
            $relative = $entry.Substring($prefix.Length)
            if ($relative -match '(^|/)\.git(/|$)|(^|/)\.env($|\.)|(^|/)\.\.?(/|$)') {
                throw "Forbidden archive entry: $entry"
            }
        }
        $tracked = @(& git -C $RepoRoot ls-files)
        if ($LASTEXITCODE -ne 0) { throw 'git ls-files failed.' }
        $archived = @($entries | ForEach-Object { $_.Substring($prefix.Length) })
        $difference = Compare-Object ($tracked | Sort-Object) ($archived | Sort-Object)
        if ($difference) { throw 'Archive contents differ from tracked files.' }
    }
    finally {
        $zip.Dispose()
    }
}
catch {
    if (Test-Path -LiteralPath $OutputPath) {
        Remove-Item -LiteralPath $OutputPath -Force
    }
    throw
}

$hash = (Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Output "PASS: $OutputPath"
Write-Output "SHA256: $hash"
