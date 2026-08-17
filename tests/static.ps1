[CmdletBinding()]
param([Parameter(Mandatory)][string]$RepoRoot)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$failures = [System.Collections.Generic.List[string]]::new()

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { $script:failures.Add($Message) }
}

function Relative-Name {
    param([string]$Path)
    $prefix = [IO.Path]::GetFullPath($RepoRoot).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $full = [IO.Path]::GetFullPath($Path)
    if ($full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($prefix.Length).Replace('\', '/')
    }
    return $full.Replace('\', '/')
}

$skillPaths = @(
    Join-Path $RepoRoot 'skills/windows-wsl-file-navigation/SKILL.md'
    Join-Path $RepoRoot 'skills/windows-python-runtime/SKILL.md'
)
$requiredSections = @(
    '## When to Use', '## Prerequisites', '## How to Run',
    '## Quick Reference', '## Procedure', '## Pitfalls', '## Verification'
)

foreach ($skillPath in $skillPaths) {
    Assert-True (Test-Path -LiteralPath $skillPath -PathType Leaf) "Missing skill: $(Relative-Name $skillPath)"
    if (-not (Test-Path -LiteralPath $skillPath -PathType Leaf)) { continue }
    $content = Get-Content -LiteralPath $skillPath -Raw
    $slug = Split-Path -Leaf (Split-Path -Parent $skillPath)
    $last = -1
    foreach ($section in $requiredSections) {
        $index = $content.IndexOf($section, [StringComparison]::Ordinal)
        Assert-True ($index -gt $last) "${slug}: missing or misordered section $section"
        if ($index -ge 0) { $last = $index }
    }
    Assert-True ($content -notmatch '(?i)\b(?:TODO|FIXME|TBD)\b') "${slug}: unfinished marker"
    Assert-True ($content.IndexOf('Remote and container terminal backends are outside the v0.1.0 scope', [StringComparison]::Ordinal) -ge 0) "${slug}: backend visibility guard missing"
}

$pathSkill = Get-Content -LiteralPath $skillPaths[0] -Raw
$pathReference = Get-Content -LiteralPath (Join-Path $RepoRoot 'skills/windows-wsl-file-navigation/references/routing-reference.md') -Raw
$pathBundle = $pathSkill + "`n" + $pathReference
foreach ($required in @(
    'Hermes file tools via native Windows',
    'Hermes file tools via WSL',
    'execution backend used by `search_files` and `read_file`',
    'C:/...', '/mnt/c/...', '/home/...', 'capability probe',
    'MSYS_NO_PATHCONV=1', "MSYS2_ARG_CONV_EXCL='*'",
    'shell interpreter itself as a trust boundary',
    'test -e', 'test -x', 'Git Bash result never proves WSL ownership',
    'CRLF', 'verify the received value', '(?:- Use)',
    'relative root beginning with `-`', 'unexpected help/version output'
)) {
    Assert-True ($pathBundle.IndexOf($required, [StringComparison]::OrdinalIgnoreCase) -ge 0) "Path contract missing: $required"
}
Assert-True ($pathSkill.IndexOf('| Hermes native file tools |', [StringComparison]::OrdinalIgnoreCase) -lt 0) 'Universal native-Windows Hermes route is forbidden'
Assert-True ($pathReference -match '(?s)fallback is only for native Windows Hermes backends.*?/mnt/') 'Legacy recovery must exclude WSL backends'

$pythonSkill = Get-Content -LiteralPath $skillPaths[1] -Raw
$pythonReference = Get-Content -LiteralPath (Join-Path $RepoRoot 'skills/windows-python-runtime/references/interpreter-reference.md') -Raw
$pythonResolverPath = Join-Path $RepoRoot 'skills/windows-python-runtime/scripts/resolve-python-runtime.ps1'
Assert-True (Test-Path -LiteralPath $pythonResolverPath -PathType Leaf) 'Python resolver script is missing'
$pythonResolver = if (Test-Path -LiteralPath $pythonResolverPath -PathType Leaf) { Get-Content -LiteralPath $pythonResolverPath -Raw } else { '' }
$pythonBundle = $pythonSkill + "`n" + $pythonReference + "`n" + $pythonResolver
foreach ($required in @(
    'PYTHON_MANAGER_AUTOMATIC_INSTALL', '-0p', 'pymanager.exe',
    'Test-PsfSignedExecutable', 'Test-OfficialPythonManagerAlias',
    'Test-OfficialPythonRuntimeAlias', 'Get-AuthenticodeSignature',
    'Test-LocalFixedPathWithoutReparsePoints', '__PYVENV_LAUNCHER__', 'PYTHONEXECUTABLE',
    'Test-RuntimeStartupIsolation', 'RuntimeTarget', '._pth',
    'Get-EffectiveRequiredArchitecture', 'RequiredArchitecture',
    'PSModulePath', 'WSLENV', '${HERMES_SKILL_DIR}',
    'Never use the launcher to start the candidate',
    'stop without launching a runtime', 'inventory row',
    'non-absolute runtime path', '-I -S -B',
    'Venv identity probe failed', 'sitecustomize',
    'python3.14t.exe', 'Version range is the only evidence',
    'command -v', 'python<major>.<minor>',
    'file -L', 'readlink -f', 'test -e', 'test -x',
    'distribution remains plausible', 'series-only'
)) {
    Assert-True ($pythonBundle.IndexOf($required, [StringComparison]::OrdinalIgnoreCase) -ge 0) "Python contract missing: $required"
}

$inFence = $false
foreach ($line in ($pythonBundle.Replace("`r`n", "`n") -split "`n")) {
    if ($line -match '^```') { $inFence = -not $inFence; continue }
    if (-not $inFence) { continue }
    $unsafeStart = '^\s*(?:&\s*)?(?:py(?:\.exe)?|pymanager(?:\.exe)?)\s+(?:-3(?:\.\d+)?\b|-V:|exec\b|install\b)'
    Assert-True (-not ($line -match $unsafeStart)) "Launcher-based runtime start/install forbidden in executable example: $line"
}
Assert-True ($pythonReference -notmatch '(?m)^\s*&\s*\$launcherPath\s+(?!-0p\b)') 'Resolved launcher may only execute the -0p inventory operation'
Assert-True ($pythonResolver -notmatch '(?m)^\s*[^#\r\n]*&\s*\$LauncherPath\s+(?!-0p\b)') 'Resolver launcher may only execute the -0p inventory operation'

Assert-True ($pathSkill.IndexOf('[`windows-python-runtime`](../windows-python-runtime/)', [StringComparison]::Ordinal) -ge 0) 'Path skill must link to its Python companion'
Assert-True ($pythonSkill.IndexOf('[`windows-wsl-file-navigation`](../windows-wsl-file-navigation/)', [StringComparison]::Ordinal) -ge 0) 'Python skill must link to its path-routing companion'
$readmePath = Join-Path $RepoRoot 'README.md'
$readme = Get-Content -LiteralPath $readmePath -Raw
Assert-True ($readme -notmatch '(?i)\baudited\b') 'README must not imply an external audit'
Assert-True ($readme.IndexOf('Docker, container, SSH, or other remote terminal backends', [StringComparison]::Ordinal) -ge 0) 'README support matrix must disclose remote backend scope'

$gitRoot = Join-Path $RepoRoot '.git'
$allItems = @(Get-ChildItem -LiteralPath $RepoRoot -Recurse -Force | Where-Object {
    $_.FullName -ne $gitRoot -and -not $_.FullName.StartsWith($gitRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
})
$files = @($allItems | Where-Object { -not $_.PSIsContainer })
$allowedExtensions = @('.md', '.ps1', '.py', '.sh', '.txt', '.yml', '.yaml')
$allowedNames = @('LICENSE', '.gitignore', '.gitattributes', '.editorconfig')

foreach ($item in $allItems) {
    Assert-True (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) "Reparse point forbidden: $(Relative-Name $item.FullName)"
}

foreach ($file in $files) {
    $extensionAllowed = $allowedExtensions -contains $file.Extension.ToLowerInvariant()
    Assert-True ($extensionAllowed -or $allowedNames -contains $file.Name) "Unexpected file type: $(Relative-Name $file.FullName)"
    Assert-True ($file.Length -le 256KB) "File exceeds 256 KiB: $(Relative-Name $file.FullName)"
    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    Assert-True (-not ($bytes -contains 0)) "NUL byte forbidden: $(Relative-Name $file.FullName)"
    $text = [IO.File]::ReadAllText($file.FullName)
    Assert-True (-not [regex]::IsMatch($text, '[\u202A-\u202E\u2066-\u2069\u200B-\u200D\uFEFF]')) "Invisible Unicode control forbidden: $(Relative-Name $file.FullName)"
    if ($env:OS -eq 'Windows_NT') {
        $streams = @(Get-Item -LiteralPath $file.FullName -Stream * -ErrorAction Stop | Where-Object { $_.Stream -ne ':$DATA' })
        Assert-True ($streams.Count -eq 0) "Alternate data stream forbidden: $(Relative-Name $file.FullName)"
    }
}

$joined = ($files | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`n"
$forbiddenPatterns = @(
    '(?i)-----BEGIN (?:OPENSSH|RSA|EC|DSA|PGP)? ?PRIVATE KEY-----',
    '(?i)\bgithub_pat_[A-Za-z0-9_]{20,}',
    '(?i)\bgh[pousr]_[A-Za-z0-9]{20,}',
    '(?i)\bsk-[A-Za-z0-9_-]{20,}',
    '(?i)\bAKIA[0-9A-Z]{16}\b',
    '(?i)\bAIza[0-9A-Za-z_-]{30,}',
    '(?i)\bxox[baprs]-[A-Za-z0-9-]{10,}',
    '(?i)https?://[^\s/:]+:[^\s/@]+@',
    '(?i)Authorization\s*:\s*Bearer\s+\S+',
    '(?i)<(?:environment_context|skills_instructions|apps_instructions)\b',
    '(?im)^Co-authored-by:\s*\S',
    '(?i)\.codex[\\/]',
    '(?i)\.claude[\\/]'
    '(?i)(?:[A-Z]:[\\/]|/[a-z]/|/mnt/[a-z]/)Users[\\/][A-Za-z0-9][A-Za-z0-9._-]*(?:[\\/]|$)'
)
foreach ($pattern in $forbiddenPatterns) {
    Assert-True (-not [regex]::IsMatch($joined, $pattern)) "Forbidden publication pattern detected: $pattern"
}

$localMarkers = @($env:USERPROFILE, $env:LOCALAPPDATA, $env:APPDATA) | Where-Object { $_ -and $_.Length -ge 6 }
foreach ($marker in $localMarkers) {
    Assert-True ($joined.IndexOf($marker, [StringComparison]::OrdinalIgnoreCase) -lt 0) 'Local machine path detected'
}

if ($failures.Count -gt 0) {
    Write-Error ("Static validation failed:`n - " + ($failures -join "`n - "))
    exit 1
}

Write-Output "PASS: static contracts and $($files.Count) repository files validated."
