[CmdletBinding()]
param(
    [ValidatePattern('^\d+\.\d+t?(?:-(?:32|64|arm64))?$')]
    [string]$RequiredTag,

    [ValidatePattern('^\d+\.\d+(?:\.\d+)?$')]
    [string]$ExpectedVersion
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

foreach ($moduleName in @('Microsoft.PowerShell.Management', 'Microsoft.PowerShell.Utility')) {
    $modulePath = [IO.Path]::Combine($PSHOME, 'Modules', $moduleName, "$moduleName.psd1")
    if (-not [IO.File]::Exists($modulePath)) {
        throw "Required built-in PowerShell module is missing: $moduleName"
    }
    Microsoft.PowerShell.Core\Import-Module -Name $modulePath -Force -ErrorAction Stop
}

function Set-ProcessEnvironmentValue {
    param(
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][object]$Value
    )

    if ($null -eq $Value) {
        [Environment]::SetEnvironmentVariable(
            $Name,
            [System.Management.Automation.Language.NullString]::Value,
            'Process'
        )
    }
    else {
        [Environment]::SetEnvironmentVariable($Name, [string]$Value, 'Process')
    }
}

function Test-FullyQualifiedWindowsPath {
    param([Parameter(Mandatory)][string]$Path)

    if ($Path -notmatch '^[A-Za-z]:[\\/]') { return $false }
    try {
        $drive = [IO.DriveInfo]::new([IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Path)))
        return $drive.IsReady -and $drive.DriveType -eq [IO.DriveType]::Fixed
    }
    catch {
        return $false
    }
}

function Test-LocalFixedPathWithoutReparsePoints {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-FullyQualifiedWindowsPath -Path $Path)) { return $false }
    try {
        $fullPath = [IO.Path]::GetFullPath($Path)
        $current = [IO.Path]::GetPathRoot($fullPath)
        $relative = $fullPath.Substring($current.Length)
        foreach ($part in $relative.Split([char[]]@('\', '/'), [StringSplitOptions]::RemoveEmptyEntries)) {
            $current = [IO.Path]::Combine($current, $part)
            $item = Microsoft.PowerShell.Management\Get-Item -LiteralPath $current -Force -ErrorAction Stop
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
        }
        return $true
    }
    catch {
        return $false
    }
}

function Test-PsfSignedExecutable {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string[]]$ExpectedOriginalFilename
    )

    try {
        $securityModule = [IO.Path]::Combine($PSHOME, 'Modules', 'Microsoft.PowerShell.Security', 'Microsoft.PowerShell.Security.psd1')
        Microsoft.PowerShell.Core\Import-Module -Name $securityModule -Force -ErrorAction Stop
        if (-not (Test-LocalFixedPathWithoutReparsePoints -Path $Path)) { return $false }
        $item = Microsoft.PowerShell.Management\Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if ($item.PSIsContainer -or $item.Length -le 0) { return $false }
        $signature = Microsoft.PowerShell.Security\Get-AuthenticodeSignature -LiteralPath $item.FullName -ErrorAction Stop
        if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) { return $false }
        if ($null -eq $signature.SignerCertificate) { return $false }
        if ($signature.SignerCertificate.Subject -notmatch '(?:^|,\s*)O=Python Software Foundation(?:,|$)') {
            return $false
        }
        if ($ExpectedOriginalFilename -and $ExpectedOriginalFilename -notcontains $item.VersionInfo.OriginalFilename) {
            return $false
        }
        return $true
    }
    catch {
        return $false
    }
}

function Import-BuiltinAppxModule {
    $module = [IO.Path]::Combine([Environment]::SystemDirectory, 'WindowsPowerShell', 'v1.0', 'Modules', 'Appx', 'Appx.psd1')
    Microsoft.PowerShell.Core\Import-Module -Name $module -Force -ErrorAction Stop
}

function Get-AppExecLinkPayload {
    param([Parameter(Mandatory)][string]$Path)

    if (-not ('RuntimeSkills.NativeReparseReader' -as [type])) {
        Microsoft.PowerShell.Utility\Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace RuntimeSkills {
    public static class NativeReparseReader {
        private const uint FsctlGetReparsePoint = 0x000900A8;
        private const uint OpenReparsePoint = 0x00200000;
        private const uint BackupSemantics = 0x02000000;

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern SafeFileHandle CreateFileW(
            string name, uint access, FileShare share, IntPtr security,
            FileMode mode, uint flags, IntPtr template);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool DeviceIoControl(
            SafeFileHandle device, uint code, IntPtr inBuffer, int inSize,
            byte[] outBuffer, int outSize, out int returned, IntPtr overlapped);

        public static byte[] Read(string path) {
            using (SafeFileHandle handle = CreateFileW(
                path, 0, FileShare.Read | FileShare.Write | FileShare.Delete,
                IntPtr.Zero, FileMode.Open, OpenReparsePoint | BackupSemantics,
                IntPtr.Zero)) {
                if (handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
                byte[] buffer = new byte[16384];
                int returned;
                if (!DeviceIoControl(handle, FsctlGetReparsePoint, IntPtr.Zero, 0,
                    buffer, buffer.Length, out returned, IntPtr.Zero)) {
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                }
                byte[] result = new byte[returned];
                Buffer.BlockCopy(buffer, 0, result, 0, returned);
                return result;
            }
        }
    }
}
'@
    }

    $bytes = [RuntimeSkills.NativeReparseReader]::Read($Path)
    if ($bytes.Length -lt 8) { throw 'Reparse data is truncated.' }
    $tag = [BitConverter]::ToUInt32($bytes, 0)
    $length = [BitConverter]::ToUInt16($bytes, 4)
    if ($tag -ne [uint32]2147483675 -or $length -le 4 -or (8 + $length) -gt $bytes.Length) {
        throw 'The reparse point is not a valid AppExecLink.'
    }
    $declaredEntries = [BitConverter]::ToUInt32($bytes, 8)
    $decoded = [Text.Encoding]::Unicode.GetString($bytes, 12, $length - 4)
    $entries = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in $decoded.Split([char]0)) {
        if (-not [string]::IsNullOrEmpty($entry)) { $entries.Add($entry) }
    }
    if ($declaredEntries -lt 3 -or $entries.Count -lt 3) { throw 'AppExecLink data is incomplete.' }
    return [pscustomobject]@{ DeclaredEntries = $declaredEntries; Entries = $entries.ToArray() }
}

function Test-AppExecLinkBinding {
    param(
        [Parameter(Mandatory)]$Link,
        [Parameter(Mandatory)]$Package,
        [Parameter(Mandatory)]$Application
    )

    try {
        if ($Link.Entries.Count -lt 3) { return $false }
        $family = "$($Package.PackageFamilyName)"
        $identity = "$family!$($Application.Id)"
        $target = [IO.Path]::GetFullPath($Link.Entries[2])
        $expectedTarget = [IO.Path]::GetFullPath([IO.Path]::Combine("$($Package.InstallLocation)", "$($Application.Executable)"))
        return $Link.Entries[0].Equals($family, [StringComparison]::OrdinalIgnoreCase) -and
            $Link.Entries[1].Equals($identity, [StringComparison]::OrdinalIgnoreCase) -and
            $target.Equals($expectedTarget, [StringComparison]::OrdinalIgnoreCase)
    }
    catch {
        return $false
    }
}

function Test-OfficialPythonManagerAlias {
    param([Parameter(Mandatory)][string]$Path)

    try {
        $expected = [IO.Path]::Combine([Environment]::GetFolderPath('LocalApplicationData'), 'Microsoft', 'WindowsApps', 'pymanager.exe')
        $actual = [IO.Path]::GetFullPath($Path)
        if (-not $actual.Equals([IO.Path]::GetFullPath($expected), [StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }

        $item = Microsoft.PowerShell.Management\Get-Item -LiteralPath $actual -Force -ErrorAction Stop
        if ($item.PSIsContainer -or $item.Length -ne 0 -or
            -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            return $false
        }
        $link = Get-AppExecLinkPayload -Path $actual
        Import-BuiltinAppxModule
        $officialPublisherIds = @('qbz5n2kfra8p0', '3847v3x7pw1km')
        foreach ($package in @(Appx\Get-AppxPackage -Name 'PythonSoftwareFoundation.PythonManager' -ErrorAction Stop)) {
            if ($package.Status -ne 'Ok' -or $officialPublisherIds -notcontains $package.PublisherId) { continue }
            $manifest = Appx\Get-AppxPackageManifest -Package $package -ErrorAction Stop
            foreach ($application in @($manifest.Package.Applications.Application)) {
                if ($application.OuterXml -match '(?i)Alias="pymanager\.exe"' -and
                    (Test-AppExecLinkBinding -Link $link -Package $package -Application $application)) {
                    return $true
                }
            }
        }
    }
    catch {
        return $false
    }
    return $false
}

function Get-TrustedPythonLauncher {
    $managerPath = [IO.Path]::Combine(
        [Environment]::GetFolderPath('LocalApplicationData'),
        'Microsoft', 'WindowsApps', 'pymanager.exe'
    )
    if (Test-OfficialPythonManagerAlias -Path $managerPath) {
        return [IO.Path]::GetFullPath($managerPath)
    }

    $classicCandidates = @(
        [IO.Path]::Combine([Environment]::GetFolderPath('Windows'), 'py.exe'),
        [IO.Path]::Combine([Environment]::GetFolderPath('LocalApplicationData'), 'Programs', 'Python', 'Launcher', 'py.exe')
    )
    $classicPaths = [System.Collections.Generic.List[string]]::new()
    foreach ($classicPath in $classicCandidates) {
        if (Test-PsfSignedExecutable -Path $classicPath -ExpectedOriginalFilename @('py.exe')) {
            $classicPaths.Add([IO.Path]::GetFullPath($classicPath))
        }
    }
    if ($classicPaths.Count -gt 1) {
        throw 'Both per-machine and per-user classic launchers are trusted; refusing an ambiguous choice.'
    }
    if ($classicPaths.Count -eq 1) { return $classicPaths[0] }
    throw 'No trusted Python Software Foundation launcher was found.'
}

function Get-InstalledPythonInventory {
    param([Parameter(Mandatory)][string]$LauncherPath)

    $setting = 'PYTHON_MANAGER_AUTOMATIC_INSTALL'
    $oldValue = [Environment]::GetEnvironmentVariable($setting, 'Process')
    try {
        [Environment]::SetEnvironmentVariable($setting, 'false', 'Process')
        $rawLines = @(& $LauncherPath -0p 2>&1)
        $lines = @(foreach ($line in $rawLines) { "$line" })
        $exitCode = $LASTEXITCODE
    }
    finally {
        Set-ProcessEnvironmentValue -Name $setting -Value $oldValue
    }

    if ($exitCode -ne 0 -or $lines.Count -eq 0) {
        throw 'The trusted launcher returned no installed-runtime inventory.'
    }
    return $lines
}

function Test-InventoryTagMatch {
    param(
        [Parameter(Mandatory)][string]$InventoryTag,
        [Parameter(Mandatory)][string]$Requirement
    )

    if ($InventoryTag.Equals($Requirement, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    $requiredArchitecture = [regex]::Match($Requirement, '^(?<base>\d+(?:\.\d+)?t?)-(?:32|64|arm64)$')
    if ($requiredArchitecture.Success -and
        $InventoryTag.Equals($requiredArchitecture.Groups['base'].Value, [StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    $inventoryArchitecture = [regex]::Match($InventoryTag, '^(?<base>\d+(?:\.\d+)?t?)-(?:32|64|arm64)$')
    if ($inventoryArchitecture.Success -and
        $Requirement.Equals($inventoryArchitecture.Groups['base'].Value, [StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    return $false
}

function Select-InstalledPythonPath {
    param(
        [Parameter(Mandatory)][string[]]$Inventory,
        [Parameter(Mandatory)][string]$Requirement
    )

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($line in $Inventory) {
        $tag = $null
        $path = $null
        if ($line -match '^\s*-V:(?<tag>\S+)\s+\*?\s*(?<path>.+?)\s*$') {
            $tag = $Matches['tag']
            $path = $Matches['path']
        }
        elseif ($line -match '^\s*-(?<tag>\d+(?:\.\d+)?t?(?:-(?:32|64|arm64))?)\s+\*?\s*(?<path>.+?)\s*$') {
            $tag = $Matches['tag']
            $path = $Matches['path']
        }
        else {
            continue
        }

        if (-not (Test-InventoryTagMatch -InventoryTag $tag -Requirement $Requirement)) {
            continue
        }
        $path = $path.Trim()
        if ($path.Length -ge 2 -and (($path[0] -eq '"' -and $path[$path.Length - 1] -eq '"') -or
                ($path[0] -eq "'" -and $path[$path.Length - 1] -eq "'"))) {
            $path = $path.Substring(1, $path.Length - 2)
        }
        if (-not (Test-FullyQualifiedWindowsPath -Path $path)) {
            throw 'The launcher inventory returned a non-absolute runtime path.'
        }
        $fullPath = [IO.Path]::GetFullPath($path)
        $leaf = [IO.Path]::GetFileName($fullPath)
        if ($leaf -notmatch '^python(?:\d+(?:\.\d+)?t?)?\.exe$') {
            throw 'The launcher inventory returned an unexpected executable name.'
        }
        $rows.Add([pscustomobject]@{ Tag = $tag; Path = $fullPath })
    }

    if ($rows.Count -ne 1) {
        throw 'The required installed runtime was absent or ambiguous.'
    }
    return $rows[0]
}

function Get-EffectiveRequiredArchitecture {
    param(
        [Parameter(Mandatory)][string]$RequiredTag,
        [Parameter(Mandatory)][string]$InventoryTag
    )

    foreach ($tag in @($RequiredTag, $InventoryTag)) {
        $match = [regex]::Match(
            $tag,
            '-(?<architecture>32|64|arm64)$',
            [Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
        if ($match.Success) {
            return $match.Groups['architecture'].Value.ToLowerInvariant()
        }
    }
    return ''
}

function Resolve-OfficialPythonRuntimeAliasTarget {
    param([Parameter(Mandatory)][string]$Path)

    $item = Microsoft.PowerShell.Management\Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.PSIsContainer -or $item.Length -ne 0 -or
        -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'The runtime alias is not a zero-byte reparse point.'
    }
    $link = Get-AppExecLinkPayload -Path $item.FullName
    $windowsApps = [IO.Path]::Combine([Environment]::GetFolderPath('LocalApplicationData'), 'Microsoft', 'WindowsApps')
    $windowsApps = [IO.Path]::GetFullPath($windowsApps).TrimEnd('\')
    if (-not $item.FullName.StartsWith($windowsApps + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'The runtime alias is outside the canonical WindowsApps directory.'
    }
    $relative = $item.FullName.Substring($windowsApps.Length).TrimStart('\')
    $parts = $relative -split '\\'
    if ($parts.Count -ne 2 -or $parts[0] -notmatch '^PythonSoftwareFoundation\.Python\.[A-Za-z0-9._-]+_(?:qbz5n2kfra8p0|3847v3x7pw1km)$') {
        throw 'The runtime alias package family is not official.'
    }
    Import-BuiltinAppxModule
    $leafPattern = 'Alias="' + [regex]::Escape($parts[1]) + '"'
    $officialPublisherIds = @('qbz5n2kfra8p0', '3847v3x7pw1km')
    foreach ($package in @(Appx\Get-AppxPackage -ErrorAction Stop)) {
        if ($package.PackageFamilyName -ne $parts[0] -or $package.Status -ne 'Ok' -or
            $officialPublisherIds -notcontains $package.PublisherId) {
            continue
        }
        $manifest = Appx\Get-AppxPackageManifest -Package $package -ErrorAction Stop
        foreach ($application in @($manifest.Package.Applications.Application)) {
            if ($application.OuterXml -match ('(?i)' + $leafPattern) -and
                (Test-AppExecLinkBinding -Link $link -Package $package -Application $application)) {
                return [IO.Path]::GetFullPath($link.Entries[2])
            }
        }
    }
    throw 'The runtime alias does not bind to an installed official package.'
}

function Test-OfficialPythonRuntimeAlias {
    param([Parameter(Mandatory)][string]$Path)

    try {
        [void](Resolve-OfficialPythonRuntimeAliasTarget -Path $Path)
        return $true
    }
    catch {
        return $false
    }
}

function Resolve-TrustedInstalledRuntimeTarget {
    param([Parameter(Mandatory)][string]$Path)

    if (Test-PsfSignedExecutable -Path $Path -ExpectedOriginalFilename @('python.exe')) {
        return [IO.Path]::GetFullPath($Path)
    }
    $target = Resolve-OfficialPythonRuntimeAliasTarget -Path $Path
    if (-not (Test-PsfSignedExecutable -Path $target -ExpectedOriginalFilename @('python.exe'))) {
        throw 'The official runtime alias target is not a trusted PSF executable.'
    }
    return $target
}

function Test-TrustedInstalledRuntime {
    param([Parameter(Mandatory)][string]$Path)

    try {
        [void](Resolve-TrustedInstalledRuntimeTarget -Path $Path)
        return $true
    }
    catch {
        return $false
    }
}

function Test-RuntimeStartupIsolation {
    param(
        [Parameter(Mandatory)][string]$ExecutablePath,
        [Parameter(Mandatory)][string]$RuntimeTag,
        [Parameter(Mandatory)][string]$InvocationPath
    )

    try {
        if (-not (Test-LocalFixedPathWithoutReparsePoints -Path $ExecutablePath)) { return $false }
        $directory = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($ExecutablePath))
        $configurationDirectories = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $pthDirectories = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($configurationPath in @($ExecutablePath, $InvocationPath)) {
            if (-not (Test-FullyQualifiedWindowsPath -Path $configurationPath)) { return $false }
            $configurationDirectory = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($configurationPath))
            [void]$configurationDirectories.Add($configurationDirectory)
            [void]$pthDirectories.Add($configurationDirectory)
            $parentDirectory = [IO.Path]::GetDirectoryName($configurationDirectory)
            if ($parentDirectory) { [void]$configurationDirectories.Add($parentDirectory) }
        }
        foreach ($configurationRoot in $configurationDirectories) {
            if ([IO.File]::Exists([IO.Path]::Combine($configurationRoot, 'pyvenv.cfg'))) {
                return $false
            }
        }
        foreach ($pathDirectory in $pthDirectories) {
            if ([IO.Directory]::EnumerateFiles($pathDirectory, '*._pth', [IO.SearchOption]::TopDirectoryOnly).GetEnumerator().MoveNext()) {
                return $false
            }
        }

        $tagMatch = [regex]::Match($RuntimeTag, '^(?<major>\d+)\.(?<minor>\d+)(?<free>t?)')
        if (-not $tagMatch.Success) { return $false }
        $dllStem = 'python' + $tagMatch.Groups['major'].Value + $tagMatch.Groups['minor'].Value + $tagMatch.Groups['free'].Value
        $dllPath = [IO.Path]::Combine($directory, "$dllStem.dll")
        return Test-PsfSignedExecutable -Path $dllPath -ExpectedOriginalFilename @("$dllStem.dll")
    }
    catch {
        return $false
    }
}

function Invoke-PythonIdentityProbe {
    param(
        [Parameter(Mandatory)][string]$PythonPath,
        [Parameter(Mandatory)][string]$VersionRequirement,
        [Parameter(Mandatory)][bool]$RequireFreeThreaded,
        [ValidateSet('', '32', '64', 'arm64')][string]$RequiredArchitecture = ''
    )

    $code = 'import sys; print(sys.executable); print(''%d.%d.%d'' % sys.version_info[:3]); print(sys.prefix); print(sys.base_prefix); print(int(hasattr(sys, ''_is_gil_enabled'') and not sys._is_gil_enabled())); print(64 if sys.maxsize > 2**32 else 32); print(sys.version)'
    $identitySettings = @('__PYVENV_LAUNCHER__', 'PYTHONEXECUTABLE')
    $oldIdentityValues = @{}
    try {
        foreach ($setting in $identitySettings) {
            $oldIdentityValues[$setting] = [Environment]::GetEnvironmentVariable($setting, 'Process')
            Set-ProcessEnvironmentValue -Name $setting -Value $null
        }
        $rawOutput = @(& $PythonPath -I -S -B -c $code 2>&1)
        $output = @(foreach ($line in $rawOutput) { "$line" })
        $exitCode = $LASTEXITCODE
    }
    finally {
        foreach ($setting in $identitySettings) {
            Set-ProcessEnvironmentValue -Name $setting -Value $oldIdentityValues[$setting]
        }
    }
    if ($exitCode -ne 0 -or $output.Count -ne 7) {
        throw 'The exact installed runtime failed its isolated identity probe.'
    }

    $actualVersion = $output[1].Trim()
    if ($VersionRequirement -match '^\d+\.\d+\.\d+$') {
        if ($actualVersion -ne $VersionRequirement) { throw 'The runtime patch version does not match project evidence.' }
    }
    elseif ($actualVersion -notmatch ('^' + [regex]::Escape($VersionRequirement) + '\.\d+$')) {
        throw 'The runtime major/minor version does not match project evidence.'
    }
    if ($RequireFreeThreaded -and $output[4].Trim() -ne '1') {
        throw 'The selected runtime is not the required free-threaded build.'
    }
    if (-not $RequireFreeThreaded -and $output[4].Trim() -ne '0') {
        throw 'The selected runtime is unexpectedly free-threaded.'
    }

    $actualBits = $output[5].Trim()
    $buildIdentity = $output[6].Trim()
    if ($RequiredArchitecture -eq '32' -and $actualBits -ne '32') {
        throw 'The selected runtime does not match the required 32-bit architecture.'
    }
    if ($RequiredArchitecture -eq '64' -and
        ($actualBits -ne '64' -or $buildIdentity -notmatch '\(AMD64\)')) {
        throw 'The selected runtime does not match the required x64 architecture.'
    }
    if ($RequiredArchitecture -eq 'arm64' -and
        ($actualBits -ne '64' -or $buildIdentity -notmatch '\(ARM64\)')) {
        throw 'The selected runtime does not match the required ARM64 architecture.'
    }

    $actualArchitecture = if ($actualBits -eq '32') {
        'x86'
    }
    elseif ($buildIdentity -match '\(ARM64\)') {
        'arm64'
    }
    elseif ($buildIdentity -match '\(AMD64\)') {
        'x64'
    }
    else {
        'unknown-64'
    }

    return [pscustomobject]@{
        Executable = $output[0].Trim()
        Version = $actualVersion
        Prefix = $output[2].Trim()
        BasePrefix = $output[3].Trim()
        FreeThreaded = ($output[4].Trim() -eq '1')
        Architecture = $actualArchitecture
    }
}

function Test-ReportedPythonPath {
    param(
        [Parameter(Mandatory)][string]$SelectedPath,
        [Parameter(Mandatory)][string]$ReportedPath
    )

    if (-not (Test-FullyQualifiedWindowsPath -Path $ReportedPath)) { return $false }
    try {
        $selected = [IO.Path]::GetFullPath($SelectedPath)
        $reported = [IO.Path]::GetFullPath($ReportedPath)
        return $selected.Equals($reported, [StringComparison]::OrdinalIgnoreCase)
    }
    catch {
        return $false
    }
}

if ($MyInvocation.InvocationName -eq '.') { return }

if ([string]::IsNullOrWhiteSpace($RequiredTag)) {
    throw 'RequiredTag is mandatory when running the resolver.'
}
$RequiredTag = $RequiredTag.ToLowerInvariant()

$series = [regex]::Match($RequiredTag, '^(?<series>\d+\.\d+)').Groups['series'].Value
if ([string]::IsNullOrWhiteSpace($ExpectedVersion)) { $ExpectedVersion = $series }
if ($ExpectedVersion -notmatch ('^' + [regex]::Escape($series) + '(?:\.\d+)?$')) {
    throw 'ExpectedVersion and RequiredTag describe different Python series.'
}

$launcherPath = Get-TrustedPythonLauncher
$inventory = @(Get-InstalledPythonInventory -LauncherPath $launcherPath)
$selected = Select-InstalledPythonPath -Inventory $inventory -Requirement $RequiredTag
$runtimeTarget = $null
try { $runtimeTarget = Resolve-TrustedInstalledRuntimeTarget -Path $selected.Path } catch { }
if ([string]::IsNullOrWhiteSpace($runtimeTarget)) {
    throw 'The inventoried runtime is not a trusted PSF executable or official AppX alias.'
}
if (-not (Test-RuntimeStartupIsolation -ExecutablePath $runtimeTarget -RuntimeTag $RequiredTag -InvocationPath $selected.Path)) {
    throw 'The runtime startup path, core DLL, or adjacent path configuration is not trusted.'
}
$requiredArchitecture = Get-EffectiveRequiredArchitecture -RequiredTag $RequiredTag -InventoryTag $selected.Tag
$identity = Invoke-PythonIdentityProbe -PythonPath $selected.Path -VersionRequirement $ExpectedVersion -RequireFreeThreaded ($RequiredTag -match '^\d+\.\d+t') -RequiredArchitecture $requiredArchitecture
if (-not (Test-ReportedPythonPath -SelectedPath $selected.Path -ReportedPath $identity.Executable)) {
    throw 'The runtime-reported executable does not match the inventoried path.'
}
if (-not $identity.Prefix.Equals($identity.BasePrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The global runtime unexpectedly initialized as a virtual environment.'
}

[pscustomobject]@{
    Launcher = $launcherPath
    InventoryTag = $selected.Tag
    SelectedPath = $selected.Path
    RuntimeTarget = $runtimeTarget
    Executable = $identity.Executable
    Version = $identity.Version
    Prefix = $identity.Prefix
    BasePrefix = $identity.BasePrefix
    FreeThreaded = $identity.FreeThreaded
    Architecture = $identity.Architecture
} | Microsoft.PowerShell.Utility\ConvertTo-Json -Depth 3
