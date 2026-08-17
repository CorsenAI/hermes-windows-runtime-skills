$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($args.Count -ne 1) { exit 64 }
[Console]::Write($args[0])
