[CmdletBinding()]
param([Parameter(Mandatory)][string]$RepoRoot)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($env:OS -ne 'Windows_NT') { throw 'The pinned linter asset in this script targets Windows x64.' }

$version = '1.7.12'
$expectedSha256 = '6e7241b51e6817ea6a047693d8e6fed13b31819c9a0dd6c5a726e1592d22f6e9'
$asset = "actionlint_${version}_windows_amd64.zip"
$url = "https://github.com/rhysd/actionlint/releases/download/v$version/$asset"
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("hermes-actionlint-{0}" -f [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot | Out-Null

try {
    $archive = Join-Path $tempRoot $asset
    Invoke-WebRequest -Uri $url -OutFile $archive -UseBasicParsing
    $actual = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expectedSha256) { throw 'actionlint archive checksum mismatch.' }
    Expand-Archive -LiteralPath $archive -DestinationPath $tempRoot
    $linter = Join-Path $tempRoot 'actionlint.exe'
    if (-not (Test-Path -LiteralPath $linter -PathType Leaf)) { throw 'actionlint executable missing from verified archive.' }

    $workflowRoot = Join-Path ([IO.Path]::GetFullPath($RepoRoot)) '.github/workflows'
    $workflows = @(Get-ChildItem -LiteralPath $workflowRoot -Filter *.yml -File)
    if ($workflows.Count -eq 0) { throw 'No GitHub Actions workflow found.' }
    & $linter @($workflows.FullName)
    if ($LASTEXITCODE -ne 0) { throw "actionlint failed with exit code $LASTEXITCODE." }
    Write-Output "PASS: actionlint $version validated $($workflows.Count) workflow(s)."
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
