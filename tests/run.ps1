$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
    param([Parameter(Mandatory)][string]$Message)
    $script:failures.Add($Message)
}

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )
    if (-not $Condition) { Add-Failure $Message }
}

function Get-RelativeName {
    param([Parameter(Mandatory)][string]$Path)
    $rootPrefix = [IO.Path]::GetFullPath($repoRoot).TrimEnd('\') + '\'
    $fullPath = [IO.Path]::GetFullPath($Path)
    if ($fullPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        return $fullPath.Substring($rootPrefix.Length).Replace('\', '/')
    }
    return $fullPath.Replace('\', '/')
}

$skillPaths = @(
    Join-Path $repoRoot 'skills/windows-wsl-file-navigation/SKILL.md'
    Join-Path $repoRoot 'skills/windows-python-runtime/SKILL.md'
)

$requiredSections = @(
    '## When to Use',
    '## Prerequisites',
    '## How to Run',
    '## Quick Reference',
    '## Procedure',
    '## Pitfalls',
    '## Verification'
)

foreach ($skillPath in $skillPaths) {
    Assert-True (Test-Path -LiteralPath $skillPath -PathType Leaf) "Missing skill: $(Get-RelativeName $skillPath)"
    if (-not (Test-Path -LiteralPath $skillPath -PathType Leaf)) { continue }

    $content = Get-Content -LiteralPath $skillPath -Raw
    $slug = Split-Path -Leaf (Split-Path -Parent $skillPath)

    $normalized = $content.Replace("`r`n", "`n")
    $lines = @($normalized -split "`n")
    Assert-True ($lines.Count -gt 2 -and $lines[0] -eq '---') "${slug}: frontmatter must start on line one"
    $frontmatterEnd = -1
    for ($lineIndex = 1; $lineIndex -lt $lines.Count; $lineIndex++) {
        if ($lines[$lineIndex] -eq '---') {
            $frontmatterEnd = $lineIndex
            break
        }
    }
    Assert-True ($frontmatterEnd -gt 1) "${slug}: frontmatter closing marker missing"
    if ($frontmatterEnd -gt 1) {
        $frontmatterText = ($lines[1..($frontmatterEnd - 1)] -join "`n")
        Assert-True ($frontmatterText.IndexOf("`t", [StringComparison]::Ordinal) -lt 0) "${slug}: tabs forbidden in frontmatter"
        Assert-True ($frontmatterText -match '(?m)^metadata:$') "${slug}: metadata mapping missing"
        Assert-True ($frontmatterText -match '(?m)^  hermes:$') "${slug}: Hermes metadata mapping missing"
        Assert-True ($frontmatterText -match '(?m)^    requires_tools: \[terminal, search_files, read_file\]$') "${slug}: required tools mismatch"
        $bodyText = ($lines[($frontmatterEnd + 1)..($lines.Count - 1)] -join "`n").Trim()
        Assert-True ($bodyText.Length -gt 0) "${slug}: body missing"
    }

    Assert-True ($content -match "(?m)^name: $([regex]::Escape($slug))$") "${slug}: frontmatter name mismatch"
    Assert-True ($content -match '(?m)^version: 0\.1\.0$') "${slug}: version missing"
    Assert-True ($content -match '(?m)^author: CorsenAI$') "${slug}: author mismatch"
    Assert-True ($content -match '(?m)^license: MIT$') "${slug}: license mismatch"
    Assert-True ($content -match '(?m)^platforms: \[windows, linux\]$') "${slug}: platforms mismatch"
    Assert-True ($content -notmatch '(?i)\b(?:TODO|FIXME|TBD)\b') "${slug}: unfinished marker"

    $descriptionMatch = [regex]::Match($content, '(?m)^description: (?<value>.+)$')
    Assert-True $descriptionMatch.Success "${slug}: description missing"
    if ($descriptionMatch.Success) {
        $description = $descriptionMatch.Groups['value'].Value.Trim()
        Assert-True ($description.Length -le 60) "${slug}: description exceeds 60 characters"
        Assert-True $description.EndsWith('.') "${slug}: description must end with a period"
    }

    $lastIndex = -1
    foreach ($section in $requiredSections) {
        $index = $content.IndexOf($section, [StringComparison]::Ordinal)
        Assert-True ($index -gt $lastIndex) "${slug}: missing or misordered section $section"
        if ($index -ge 0) { $lastIndex = $index }
    }
}

$pathSkill = Get-Content -LiteralPath $skillPaths[0] -Raw
foreach ($required in @(
    'consumer', 'C:/', '/c/', '/mnt/c/', 'wsl.localhost',
    'MSYS2_ARG_CONV_EXCL', 'zero matches', 'independent route',
    'UNC round-trip'
)) {
    Assert-True ($pathSkill.IndexOf($required, [StringComparison]::OrdinalIgnoreCase) -ge 0) "Path skill missing requirement: $required"
}

$pythonSkill = Get-Content -LiteralPath $skillPaths[1] -Raw
foreach ($required in @(
    'pyvenv.cfg', 'Scripts/python.exe', 'bin/python', 'sys.executable',
    'py -3.11', 'py -3', '-m pip', 'application picker', 'zero-byte',
    'foreign interpreter', 'without Python'
)) {
    Assert-True ($pythonSkill.IndexOf($required, [StringComparison]::OrdinalIgnoreCase) -ge 0) "Python skill missing requirement: $required"
}

$pythonReferencePath = Join-Path $repoRoot 'skills/windows-python-runtime/references/interpreter-reference.md'
$pythonBundle = $pythonSkill + "`n" + (Get-Content -LiteralPath $pythonReferencePath -Raw)
$unsafeLauncherCommand = 'py' + ' list'
Assert-True ($pythonBundle.IndexOf($unsafeLauncherCommand, [StringComparison]::OrdinalIgnoreCase) -lt 0) 'Unsafe launcher command detected'

$readme = Get-Content -LiteralPath (Join-Path $repoRoot 'README.md') -Raw
foreach ($installCommand in @(
    'hermes skills tap add CorsenAI/hermes-windows-runtime-skills',
    'hermes skills install CorsenAI/hermes-windows-runtime-skills/windows-wsl-file-navigation',
    'hermes skills install CorsenAI/hermes-windows-runtime-skills/windows-python-runtime',
    'hermes skills install CorsenAI/hermes-windows-runtime-skills/skills/windows-wsl-file-navigation',
    'hermes skills install CorsenAI/hermes-windows-runtime-skills/skills/windows-python-runtime'
)) {
    Assert-True ($readme.IndexOf($installCommand, [StringComparison]::Ordinal) -ge 0) "README missing install command: $installCommand"
}

$allowedExtensions = @('.md', '.ps1', '.yml', '.yaml')
$allowedNames = @('LICENSE', '.gitignore', '.gitattributes', '.editorconfig')
$gitRoot = Join-Path $repoRoot '.git'
$allItems = @(Get-ChildItem -LiteralPath $repoRoot -Recurse -Force | Where-Object {
    $_.FullName -ne $gitRoot -and -not $_.FullName.StartsWith($gitRoot + '\', [StringComparison]::OrdinalIgnoreCase)
})
$files = @($allItems | Where-Object { -not $_.PSIsContainer })

foreach ($item in $allItems) {
    Assert-True (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) "Reparse point forbidden: $(Get-RelativeName $item.FullName)"
}

foreach ($file in $files) {
    $extensionAllowed = $allowedExtensions -contains $file.Extension.ToLowerInvariant()
    $nameAllowed = $allowedNames -contains $file.Name
    Assert-True ($extensionAllowed -or $nameAllowed) "Unexpected file type: $(Get-RelativeName $file.FullName)"
    Assert-True ($file.Length -le 256KB) "File exceeds 256 KiB: $(Get-RelativeName $file.FullName)"

    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    Assert-True (-not ($bytes -contains 0)) "NUL byte forbidden: $(Get-RelativeName $file.FullName)"

    $text = [IO.File]::ReadAllText($file.FullName)
    $invisiblePattern = '[\u202A-\u202E\u2066-\u2069\u200B-\u200D\uFEFF]'
    Assert-True (-not [regex]::IsMatch($text, $invisiblePattern)) "Invisible Unicode control forbidden: $(Get-RelativeName $file.FullName)"

    if ($env:OS -eq 'Windows_NT') {
        $extraStreams = @(Get-Item -LiteralPath $file.FullName -Stream * -ErrorAction Stop | Where-Object {
            $_.Stream -ne ':$DATA'
        })
        Assert-True ($extraStreams.Count -eq 0) "Alternate data stream forbidden: $(Get-RelativeName $file.FullName)"
    }
}

$joined = ($files | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`n"

foreach ($scannerSensitiveText in @(
    ('print' + 'env'),
    ('env' + ' |')
)) {
    Assert-True ($joined.IndexOf($scannerSensitiveText, [StringComparison]::OrdinalIgnoreCase) -lt 0) 'Community scanner-sensitive pattern detected'
}

$forbiddenLiterals = @(
    ('App' + 'Data'),
    ('.co' + 'dex/'),
    ('.clau' + 'de/'),
    ('Chat' + 'GPT'),
    ('Qw' + 'en'),
    ('Co-authored-by:' + ' Codex'),
    ('Co-authored-by:' + ' Claude')
)
foreach ($literal in $forbiddenLiterals) {
    Assert-True ($joined.IndexOf($literal, [StringComparison]::OrdinalIgnoreCase) -lt 0) 'Internal or machine-specific marker detected'
}

$profilePath = $env:USERPROFILE
$localAppPath = [Environment]::GetEnvironmentVariable(('LOCALAPP' + 'DATA'))
$roamingAppPath = [Environment]::GetEnvironmentVariable(('APP' + 'DATA'))
$userName = $env:USERNAME
$computerName = $env:COMPUTERNAME
$localPathMarkers = @($profilePath, $localAppPath, $roamingAppPath)
if ($userName) {
    $localPathMarkers += ('C:' + '\Users\' + $userName + '\')
    $localPathMarkers += "/c/Users/$userName/"
    $localPathMarkers += "/mnt/c/Users/$userName/"
}
if ($computerName) {
    $localPathMarkers += "\\$computerName\"
}
foreach ($value in ($localPathMarkers | Where-Object { $_ -and $_.Length -ge 6 } | Sort-Object -Unique)) {
    Assert-True ($joined.IndexOf($value, [StringComparison]::OrdinalIgnoreCase) -lt 0) 'Local machine path detected'
}

$personalPathPattern = '(?i)\b[A-Z]:[\\/](?:Users|Documents and Settings)[\\/][^\\/\s"<>]+'
$privateKeyPattern = '-----BEGIN ' + '(?:OPENSSH|RSA|EC|DSA|PGP)?' + ' ?PRIVATE KEY-----'
$credentialWord = '(?:api[_-]?key|client[_-]?secret|access[_-]?token|refresh[_-]?token|password|passwd|session[_-]?token)'
$credentialPattern = '(?i)\b' + $credentialWord + '\b\s*[:=]\s*["'']?[^\s"'']{8,}'
$internalPattern = '(?i)<' + '(?:environment_context|skills_instructions|apps_instructions)' + '\b'

Assert-True (-not [regex]::IsMatch($joined, $personalPathPattern)) 'Personal Windows profile path detected'
Assert-True (-not [regex]::IsMatch($joined, $privateKeyPattern)) 'Private key marker detected'
Assert-True (-not [regex]::IsMatch($joined, $credentialPattern)) 'Credential assignment detected'
Assert-True (-not [regex]::IsMatch($joined, $internalPattern)) 'Internal transcript marker detected'

if ($failures.Count -gt 0) {
    Write-Error ("Validation failed:`n - " + ($failures -join "`n - "))
    exit 1
}

Write-Output "PASS: $($skillPaths.Count) skills and $($files.Count) repository files validated."
