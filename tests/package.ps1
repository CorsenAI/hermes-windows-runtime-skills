[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][string]$PythonExe
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
$PythonExe = [IO.Path]::GetFullPath($PythonExe)
$pythonItem = Get-Item -LiteralPath $PythonExe -ErrorAction Stop
if ($pythonItem.PSIsContainer -or ($pythonItem.Length -eq 0 -and
        -not ($pythonItem.Attributes -band [IO.FileAttributes]::ReparsePoint))) {
    throw 'PythonExe must be an explicit executable file or verified reparse alias.'
}

& $PythonExe -I -S -B (Join-Path $PSScriptRoot 'package.py') `
    --repo-root $RepoRoot --output-path $OutputPath
if ($LASTEXITCODE -ne 0) {
    throw "Canonical packaging failed with exit code $LASTEXITCODE."
}
