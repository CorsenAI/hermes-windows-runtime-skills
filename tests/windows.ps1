[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$PythonExe
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($env:OS -ne 'Windows_NT') { throw 'This test requires native Windows.' }

$resolver = Join-Path $RepoRoot 'skills/windows-python-runtime/scripts/resolve-python-runtime.ps1'
. $resolver

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("hermes-skill-route-{0}" -f [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot | Out-Null
$oldPath = $env:PATH
$oldAutomaticInstall = [Environment]::GetEnvironmentVariable('PYTHON_MANAGER_AUTOMATIC_INSTALL', 'Process')
$oldPyVenvLauncher = [Environment]::GetEnvironmentVariable('__PYVENV_LAUNCHER__', 'Process')
$oldPythonExecutable = [Environment]::GetEnvironmentVariable('PYTHONEXECUTABLE', 'Process')
$oldInventoryFixture = [Environment]::GetEnvironmentVariable('HERMES_TEST_INVENTORY_RUNTIME', 'Process')

function Assert-Stops {
    param([Parameter(Mandatory)][scriptblock]$Action, [Parameter(Mandatory)][string]$Label)
    $stopped = $false
    try { & $Action }
    catch { $stopped = $true }
    if (-not $stopped) { throw "Unsafe case did not stop: $Label" }
}

try {
    $probeDir = Join-Path $tempRoot 'space ü literal-$()-!'
    New-Item -ItemType Directory -Path $probeDir | Out-Null
    $forward = $probeDir.Replace('\', '/')
    if (-not (Test-Path -LiteralPath $forward -PathType Container)) { throw 'C:/-style Windows path failed.' }
    $drive = [IO.Path]::GetPathRoot($probeDir).Substring(0, 1).ToLowerInvariant()
    $tail = $probeDir.Substring(3).Replace('\', '/')
    if (Test-Path -LiteralPath "/$drive/$tail") { throw 'MSYS path unexpectedly behaved as a native Windows path.' }
    if (Test-Path -LiteralPath "/mnt/$drive/$tail") { throw 'WSL path unexpectedly behaved as a native Windows path.' }

    $runtimeDir = Join-Path $tempRoot 'installed runtime'
    New-Item -ItemType Directory -Path $runtimeDir | Out-Null
    $runtime = Join-Path $runtimeDir 'python.exe'
    $versioned = Join-Path $runtimeDir 'python3.11.exe'
    $freeThreaded = Join-Path $runtimeDir 'python3.14t.exe'
    $debugRuntime = Join-Path $runtimeDir 'python_d.exe'
    foreach ($path in @($runtime, $versioned, $freeThreaded, $debugRuntime)) {
        [IO.File]::WriteAllText($path, 'inventory fixture')
    }

    $modern = Select-InstalledPythonPath -Inventory @(" -V:3.11 *        $runtime") -Requirement '3.11'
    if ($modern.Path -ne [IO.Path]::GetFullPath($runtime)) { throw 'Modern inventory row was not selected.' }
    $modernWithArchitecturePin = Select-InstalledPythonPath -Inventory @(" -V:3.11 *        $runtime") -Requirement '3.11-64'
    if ($modernWithArchitecturePin.Path -ne [IO.Path]::GetFullPath($runtime)) {
        throw 'A modern base tag could not defer an architecture pin to the identity probe.'
    }
    $classic = Select-InstalledPythonPath -Inventory @(" -3.11-64 *      $runtime") -Requirement '3.11'
    if ($classic.Path -ne [IO.Path]::GetFullPath($runtime)) { throw 'Classic inventory row was not selected.' }
    $versionedResult = Select-InstalledPythonPath -Inventory @(" -V:3.11          $versioned") -Requirement '3.11'
    if ($versionedResult.Path -ne [IO.Path]::GetFullPath($versioned)) { throw 'Versioned executable was rejected.' }
    $freeResult = Select-InstalledPythonPath -Inventory @(" -V:3.14t         $freeThreaded") -Requirement '3.14t'
    if ($freeResult.Path -ne [IO.Path]::GetFullPath($freeThreaded)) { throw 'Free-threaded executable was rejected.' }

    Assert-Stops -Label 'relative inventory path' -Action {
        Select-InstalledPythonPath -Inventory @(' -V:3.11          .\runtime\python.exe') -Requirement '3.11'
    }
    Assert-Stops -Label 'UNC inventory path' -Action {
        Select-InstalledPythonPath -Inventory @(' -V:3.11          \\localhost\C$\Windows\python.exe') -Requirement '3.11'
    }
    Assert-Stops -Label 'device inventory path' -Action {
        Select-InstalledPythonPath -Inventory @(' -V:3.11          \\?\C:\Windows\python.exe') -Requirement '3.11'
    }
    Assert-Stops -Label 'drive-relative inventory path' -Action {
        Select-InstalledPythonPath -Inventory @(' -V:3.11          C:python.exe') -Requirement '3.11'
    }
    Assert-Stops -Label 'missing inventory tag' -Action {
        Select-InstalledPythonPath -Inventory @(" -V:3.12          $runtime") -Requirement '3.11'
    }
    Assert-Stops -Label 'duplicate inventory tag' -Action {
        Select-InstalledPythonPath -Inventory @(" -V:3.11          $runtime", " -V:3.11          $versioned") -Requirement '3.11'
    }
    Assert-Stops -Label 'unexpected executable name' -Action {
        Select-InstalledPythonPath -Inventory @(" -V:3.11          $(Join-Path $runtimeDir 'not-python.exe')") -Requirement '3.11'
    }
    Assert-Stops -Label 'debug runtime without an explicit variant tag' -Action {
        Select-InstalledPythonPath -Inventory @(" -V:3.11          $debugRuntime") -Requirement '3.11'
    }

    if (-not (Test-PsfSignedExecutable -Path $PythonExe)) {
        throw 'The explicit release-test interpreter is not PSF-signed.'
    }
    if (Test-PsfSignedExecutable -Path $PythonExe -ExpectedOriginalFilename @('pymanager.exe')) {
        throw 'A runtime executable was accepted as the modern manager role.'
    }
    $systemClassicLauncher = [IO.Path]::Combine([Environment]::GetFolderPath('Windows'), 'py.exe')
    if ((Test-PsfSignedExecutable -Path $systemClassicLauncher -ExpectedOriginalFilename @('py.exe')) -and
        (Test-TrustedInstalledRuntime -Path $systemClassicLauncher)) {
        throw 'The classic launcher executable was accepted as a Python runtime.'
    }
    $ordinaryEmpty = Join-Path $tempRoot 'ordinary-empty.exe'
    [IO.File]::WriteAllBytes($ordinaryEmpty, [byte[]]::new(0))
    if (Test-TrustedInstalledRuntime -Path $ordinaryEmpty) { throw 'An ordinary empty file was trusted.' }

    $binding = [pscustomobject]@{
        DeclaredEntries = 3
        Entries = @('PythonSoftwareFoundation.Test_family', 'PythonSoftwareFoundation.Test_family!Python', 'C:\Program Files\Python Test\python.exe')
    }
    $bindingPackage = [pscustomobject]@{
        PackageFamilyName = 'PythonSoftwareFoundation.Test_family'
        InstallLocation = 'C:\Program Files\Python Test'
    }
    $bindingApplication = [pscustomobject]@{ Id = 'Python'; Executable = 'python.exe' }
    if (-not (Test-AppExecLinkBinding -Link $binding -Package $bindingPackage -Application $bindingApplication)) {
        throw 'A valid synthetic AppExecLink binding was rejected.'
    }
    foreach ($badEntries in @(
            @('Foreign_family', $binding.Entries[1], $binding.Entries[2]),
            @($binding.Entries[0], 'PythonSoftwareFoundation.Test_family!Foreign', $binding.Entries[2]),
            @($binding.Entries[0], $binding.Entries[1], 'C:\Program Files\Foreign\python.exe')
        )) {
        $badBinding = [pscustomobject]@{ DeclaredEntries = 3; Entries = $badEntries }
        if (Test-AppExecLinkBinding -Link $badBinding -Package $bindingPackage -Application $bindingApplication) {
            throw 'A mutated AppExecLink binding was accepted.'
        }
    }

    $managerAlias = [IO.Path]::Combine([Environment]::GetFolderPath('LocalApplicationData'), 'Microsoft', 'WindowsApps', 'pymanager.exe')
    $managerItem = $null
    try { $managerItem = Microsoft.PowerShell.Management\Get-Item -LiteralPath $managerAlias -Force -ErrorAction Stop } catch { }
    if ($managerItem) {
        if (-not (Test-OfficialPythonManagerAlias -Path $managerAlias)) {
            throw 'The installed official manager alias failed provenance validation.'
        }
        if ($managerItem.Length -ne 0 -or -not ($managerItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'The live official manager alias no longer exercises the zero-byte reparse case.'
        }
        $payload = Get-AppExecLinkPayload -Path $managerAlias
        if ($payload.DeclaredEntries -lt 3 -or $payload.Entries.Count -lt 3) {
            throw 'The live manager AppExecLink payload is incomplete.'
        }
    }

    $trustedLauncher = $null
    try { $trustedLauncher = Get-TrustedPythonLauncher } catch { }
    $shadowDir = Join-Path $tempRoot 'launcher-shadow'
    New-Item -ItemType Directory -Path $shadowDir | Out-Null
    Copy-Item -LiteralPath $PythonExe -Destination (Join-Path $shadowDir 'py.exe')
    Copy-Item -LiteralPath $PythonExe -Destination (Join-Path $shadowDir 'pymanager.exe')
    if (Test-PsfSignedExecutable -Path (Join-Path $shadowDir 'pymanager.exe') -ExpectedOriginalFilename @('pymanager.exe')) {
        throw 'A renamed PSF runtime was accepted as pymanager.exe.'
    }
    $env:PATH = $shadowDir + [IO.Path]::PathSeparator + $oldPath
    if ($trustedLauncher) {
        $expectedManager = [IO.Path]::GetFullPath($managerAlias)
        $expectedClassic = [IO.Path]::GetFullPath([IO.Path]::Combine([Environment]::GetFolderPath('Windows'), 'py.exe'))
        $expectedPerUserClassic = [IO.Path]::GetFullPath([IO.Path]::Combine([Environment]::GetFolderPath('LocalApplicationData'), 'Programs', 'Python', 'Launcher', 'py.exe'))
        if (-not $trustedLauncher.Equals($expectedManager, [StringComparison]::OrdinalIgnoreCase) -and
            -not $trustedLauncher.Equals($expectedClassic, [StringComparison]::OrdinalIgnoreCase) -and
            -not $trustedLauncher.Equals($expectedPerUserClassic, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Trusted-launcher selection escaped its deterministic locations.'
        }
        $afterShadow = Get-TrustedPythonLauncher
        if (-not $afterShadow.Equals($trustedLauncher, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'An untrusted PATH shadow changed trusted-launcher selection.'
        }
    }
    else {
        Assert-Stops -Label 'untrusted launchers only' -Action { Get-TrustedPythonLauncher }
    }
    $env:PATH = $oldPath

    & {
        function Get-AuthenticodeSignature { [pscustomobject]@{ Status = 'Valid'; SignerCertificate = [pscustomobject]@{ Subject = 'O=Python Software Foundation' } } }
        function Get-Item { [pscustomobject]@{ PSIsContainer = $false; Length = 1; FullName = $ordinaryEmpty; Attributes = 0; VersionInfo = [pscustomobject]@{ OriginalFilename = 'py.exe' } } }
        function Get-Command { [pscustomobject]@{ Source = $ordinaryEmpty } }
        function Get-AppxPackage { throw 'A shadowed Appx function was invoked.' }
        if (Test-PsfSignedExecutable -Path $ordinaryEmpty -ExpectedOriginalFilename @('py.exe')) {
            throw 'Session function shadows bypassed the signed-executable checks.'
        }
        if ($trustedLauncher) {
            $shadowProof = Get-TrustedPythonLauncher
            if (-not $shadowProof.Equals($trustedLauncher, [StringComparison]::OrdinalIgnoreCase)) {
                throw 'Session function shadows changed trusted-launcher selection.'
            }
        }
    }

    $junction = Join-Path $tempRoot 'runtime-junction'
    try {
        New-Item -ItemType Junction -Path $junction -Target $runtimeDir -ErrorAction Stop | Out-Null
        if (Test-LocalFixedPathWithoutReparsePoints -Path (Join-Path $junction 'python.exe')) {
            throw 'A runtime path traversing a junction was accepted.'
        }
        if (Test-PsfSignedExecutable -Path (Join-Path $junction 'python.exe')) {
            throw 'A signed executable reached through a junction was accepted.'
        }
    }
    catch {
        if ($_.Exception.Message -like '*was accepted*') { throw }
        Write-Output 'SKIP: this Windows host could not create the junction test fixture.'
    }

    & $PythonExe -I -S -B -c 'import sys; raise SystemExit(0 if sys.executable else 2)'
    if ($LASTEXITCODE -ne 0) { throw 'Exact interpreter invocation failed.' }

    $versionCode = "import sys; print('%d.%d.%d' % sys.version_info[:3])"
    $versionOutput = @(& $PythonExe -I -S -B -c $versionCode)
    if ($LASTEXITCODE -ne 0 -or $versionOutput.Count -ne 1 -or "$($versionOutput[0])" -notmatch '^\d+\.\d+\.\d+$') {
        throw 'Could not establish the explicit release-test interpreter version.'
    }
    $exactVersion = "$($versionOutput[0])".Trim()
    $series = ([regex]::Match($exactVersion, '^\d+\.\d+')).Value

    if (-not (Test-ReportedPythonPath -SelectedPath $PythonExe -ReportedPath $PythonExe)) {
        throw 'An identical runtime-reported path was rejected.'
    }
    if (Test-ReportedPythonPath -SelectedPath $PythonExe -ReportedPath $runtime) {
        throw 'A mismatched runtime-reported path was accepted.'
    }
    if (Test-ReportedPythonPath -SelectedPath $PythonExe -ReportedPath '.\python.exe') {
        throw 'A relative runtime-reported path was accepted.'
    }

    [Environment]::SetEnvironmentVariable('__PYVENV_LAUNCHER__', 'C:\foreign-env\Scripts\python.exe', 'Process')
    [Environment]::SetEnvironmentVariable('PYTHONEXECUTABLE', 'C:\foreign-env\python.exe', 'Process')
    $identity = Invoke-PythonIdentityProbe -PythonPath $PythonExe -VersionRequirement $exactVersion -RequireFreeThreaded $false
    if (-not (Test-ReportedPythonPath -SelectedPath $PythonExe -ReportedPath $identity.Executable)) {
        throw '__PYVENV_LAUNCHER__ spoofed the strict identity probe.'
    }
    if ([Environment]::GetEnvironmentVariable('__PYVENV_LAUNCHER__', 'Process') -ne 'C:\foreign-env\Scripts\python.exe') {
        throw '__PYVENV_LAUNCHER__ was not restored after the strict probe.'
    }
    if ([Environment]::GetEnvironmentVariable('PYTHONEXECUTABLE', 'Process') -ne 'C:\foreign-env\python.exe') {
        throw 'PYTHONEXECUTABLE was not restored after the strict probe.'
    }
    Set-ProcessEnvironmentValue -Name '__PYVENV_LAUNCHER__' -Value $oldPyVenvLauncher
    Set-ProcessEnvironmentValue -Name 'PYTHONEXECUTABLE' -Value $oldPythonExecutable
    if ($identity.Architecture -eq 'x64') {
        [void](Invoke-PythonIdentityProbe -PythonPath $PythonExe -VersionRequirement $exactVersion -RequireFreeThreaded $false -RequiredArchitecture '64')
        Assert-Stops -Label '32-bit tag mapped to x64 runtime' -Action {
            Invoke-PythonIdentityProbe -PythonPath $PythonExe -VersionRequirement $exactVersion -RequireFreeThreaded $false -RequiredArchitecture '32'
        }
        Assert-Stops -Label 'ARM64 tag mapped to x64 runtime' -Action {
            Invoke-PythonIdentityProbe -PythonPath $PythonExe -VersionRequirement $exactVersion -RequireFreeThreaded $false -RequiredArchitecture 'arm64'
        }
        $inventoryArchitecture = Get-EffectiveRequiredArchitecture -RequiredTag $series -InventoryTag "$series-32"
        if ($inventoryArchitecture -ne '32') {
            throw 'An architecture suffix from classic inventory was not preserved.'
        }
        Assert-Stops -Label 'classic 32-bit inventory mapped to x64 runtime' -Action {
            Invoke-PythonIdentityProbe -PythonPath $PythonExe -VersionRequirement $exactVersion -RequireFreeThreaded $false -RequiredArchitecture $inventoryArchitecture
        }
    }

    $inventoryFixture = Join-Path $tempRoot 'inventory-launcher.cmd'
    $emptyInventoryFixture = Join-Path $tempRoot 'empty-inventory-launcher.cmd'
    $failingInventoryFixture = Join-Path $tempRoot 'failing-inventory-launcher.cmd'
    $inventoryContent = @(
        '@echo off'
        'if not "%~1"=="-0p" exit /b 41'
        'if not "%PYTHON_MANAGER_AUTOMATIC_INSTALL%"=="false" exit /b 42'
        'echo -V:3.11 %HERMES_TEST_INVENTORY_RUNTIME%'
        'exit /b 0'
        ''
    ) -join "`r`n"
    [IO.File]::WriteAllText($inventoryFixture, $inventoryContent, [Text.Encoding]::ASCII)
    [IO.File]::WriteAllText($emptyInventoryFixture, "@echo off`r`nexit /b 0`r`n", [Text.Encoding]::ASCII)
    [IO.File]::WriteAllText($failingInventoryFixture, "@echo off`r`nexit /b 7`r`n", [Text.Encoding]::ASCII)
    [Environment]::SetEnvironmentVariable('HERMES_TEST_INVENTORY_RUNTIME', $runtime, 'Process')

    [Environment]::SetEnvironmentVariable('PYTHON_MANAGER_AUTOMATIC_INSTALL', 'sentinel', 'Process')
    $fixtureInventory = @(Get-InstalledPythonInventory -LauncherPath $inventoryFixture)
    if ($fixtureInventory.Count -ne 1 -or $fixtureInventory[0] -notmatch '^-V:3\.11 ') {
        throw 'The compatibility inventory operation returned unexpected output.'
    }
    if ([Environment]::GetEnvironmentVariable('PYTHON_MANAGER_AUTOMATIC_INSTALL', 'Process') -ne 'sentinel') {
        throw 'A pre-existing automatic-install setting was not restored.'
    }
    Set-ProcessEnvironmentValue -Name 'PYTHON_MANAGER_AUTOMATIC_INSTALL' -Value $null
    [void](Get-InstalledPythonInventory -LauncherPath $inventoryFixture)
    if ($null -ne [Environment]::GetEnvironmentVariable('PYTHON_MANAGER_AUTOMATIC_INSTALL', 'Process')) {
        throw 'An absent automatic-install setting was not restored.'
    }
    Assert-Stops -Label 'empty installed-runtime inventory' -Action {
        Get-InstalledPythonInventory -LauncherPath $emptyInventoryFixture
    }
    Assert-Stops -Label 'failed installed-runtime inventory' -Action {
        Get-InstalledPythonInventory -LauncherPath $failingInventoryFixture
    }

    if ($trustedLauncher) {
        $liveInventory = @(Get-InstalledPythonInventory -LauncherPath $trustedLauncher)
        $liveSelected = $null
        try { $liveSelected = Select-InstalledPythonPath -Inventory $liveInventory -Requirement $series } catch { }
        if ($liveSelected) {
            $liveTarget = Resolve-TrustedInstalledRuntimeTarget -Path $liveSelected.Path
            if (-not (Test-RuntimeStartupIsolation -ExecutablePath $liveTarget -RuntimeTag $series -InvocationPath $liveSelected.Path)) {
                throw 'The live installed runtime failed startup-isolation validation.'
            }
            $isolationParent = Join-Path $tempRoot 'startup-isolation'
            $isolationDir = Join-Path $isolationParent 'runtime'
            New-Item -ItemType Directory -Path $isolationDir | Out-Null
            $isolatedExe = Join-Path $isolationDir ([IO.Path]::GetFileName($liveTarget))
            $dllStem = 'python' + $series.Replace('.', '')
            $liveDll = Join-Path ([IO.Path]::GetDirectoryName($liveTarget)) "$dllStem.dll"
            Copy-Item -LiteralPath $liveTarget -Destination $isolatedExe
            Copy-Item -LiteralPath $liveDll -Destination (Join-Path $isolationDir "$dllStem.dll")
            if (-not (Test-RuntimeStartupIsolation -ExecutablePath $isolatedExe -RuntimeTag $series -InvocationPath $isolatedExe)) {
                throw 'A clean signed startup-isolation fixture was rejected.'
            }
            $aliasDir = Join-Path $isolationParent 'alias'
            New-Item -ItemType Directory -Path $aliasDir | Out-Null
            $aliasPath = Join-Path $aliasDir 'python.exe'
            [IO.File]::WriteAllBytes($aliasPath, [byte[]]::new(0))
            [IO.File]::WriteAllText((Join-Path $aliasDir 'python._pth'), "import site`n")
            if (Test-RuntimeStartupIsolation -ExecutablePath $isolatedExe -RuntimeTag $series -InvocationPath $aliasPath) {
                throw 'An invocation-alias ._pth startup override was accepted.'
            }
            Remove-Item -LiteralPath $aliasDir -Recurse -Force
            $pthFixture = Join-Path $isolationDir 'python._pth'
            [IO.File]::WriteAllText($pthFixture, "import site`n")
            if (Test-RuntimeStartupIsolation -ExecutablePath $isolatedExe -RuntimeTag $series -InvocationPath $isolatedExe) {
                throw 'An adjacent ._pth startup override was accepted.'
            }
            Remove-Item -LiteralPath $pthFixture -Force
            $localVenvConfig = Join-Path $isolationDir 'pyvenv.cfg'
            [IO.File]::WriteAllText($localVenvConfig, "home = C:/foreign`n")
            if (Test-RuntimeStartupIsolation -ExecutablePath $isolatedExe -RuntimeTag $series -InvocationPath $isolatedExe) {
                throw 'An adjacent pyvenv.cfg startup override was accepted.'
            }
            Remove-Item -LiteralPath $localVenvConfig -Force
            $parentVenvConfig = Join-Path $isolationParent 'pyvenv.cfg'
            [IO.File]::WriteAllText($parentVenvConfig, "home = C:/foreign`n")
            if (Test-RuntimeStartupIsolation -ExecutablePath $isolatedExe -RuntimeTag $series -InvocationPath $isolatedExe) {
                throw 'A parent pyvenv.cfg startup override was accepted.'
            }
            Remove-Item -LiteralPath $parentVenvConfig -Force

            $systemPowerShell = [IO.Path]::Combine([Environment]::SystemDirectory, 'WindowsPowerShell', 'v1.0', 'powershell.exe')
            $currentPowerShell = if ($PSVersionTable.PSVersion.Major -ge 6) {
                [IO.Path]::Combine($PSHOME, 'pwsh.exe')
            }
            else {
                [IO.Path]::Combine($PSHOME, 'powershell.exe')
            }
            $powerShellHosts = @($systemPowerShell, $currentPowerShell) | Sort-Object -Unique
            $oldModulePath = [Environment]::GetEnvironmentVariable('PSModulePath', 'Process')
            try {
                [Environment]::SetEnvironmentVariable('PSModulePath', (Join-Path $tempRoot 'no-modules'), 'Process')
                foreach ($hostPath in $powerShellHosts) {
                    $resolvedJson = @(& $hostPath -NoProfile -NonInteractive -File $resolver -RequiredTag $series -ExpectedVersion $exactVersion)
                    if ($LASTEXITCODE -ne 0 -or $resolvedJson.Count -eq 0) {
                        throw 'The full resolver failed with an untrusted PSModulePath.'
                    }
                    $resolved = ($resolvedJson -join "`n") | Microsoft.PowerShell.Utility\ConvertFrom-Json
                    if (-not (Test-ReportedPythonPath -SelectedPath $resolved.SelectedPath -ReportedPath $resolved.Executable) -or
                        $resolved.Version -ne $exactVersion) {
                        throw 'The full global-runtime resolver returned an inconsistent identity.'
                    }
                }
            }
            finally {
                Set-ProcessEnvironmentValue -Name 'PSModulePath' -Value $oldModulePath
            }
        }
        else {
            Write-Output "SKIP: trusted launcher has no installed $series runtime for the full-pipeline test."
        }
    }

    $fixtureVenv = Join-Path $tempRoot 'fixture-venv'
    & $PythonExe -I -B -m venv --without-pip $fixtureVenv
    if ($LASTEXITCODE -ne 0) { throw 'Could not create the isolated test venv fixture.' }
    $fixturePython = Join-Path $fixtureVenv 'Scripts/python.exe'
    $canary = Join-Path $tempRoot 'site-hook-ran.txt'
    $canaryLiteral = $canary.Replace('\', '\\').Replace("'", "\'")
    $pth = Join-Path $fixtureVenv 'Lib/site-packages/release-test.pth'
    [IO.File]::WriteAllText($pth, "import pathlib; pathlib.Path('$canaryLiteral').write_text('active')`n")

    & $fixturePython -I -S -B -c 'import sys; raise SystemExit(0 if sys.executable else 2)'
    if ($LASTEXITCODE -ne 0 -or (Test-Path -LiteralPath $canary)) {
        throw 'The strict identity probe executed a site hook.'
    }
    & $fixturePython -I -B -c 'import sys; raise SystemExit(0 if sys.prefix != sys.base_prefix else 3)'
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $canary)) {
        throw 'The active-probe fixture no longer demonstrates site-hook execution.'
    }

    Write-Output 'PASS: native Windows path and trusted-runtime contracts validated.'
}
finally {
    $env:PATH = $oldPath
    Set-ProcessEnvironmentValue -Name 'PYTHON_MANAGER_AUTOMATIC_INSTALL' -Value $oldAutomaticInstall
    Set-ProcessEnvironmentValue -Name '__PYVENV_LAUNCHER__' -Value $oldPyVenvLauncher
    Set-ProcessEnvironmentValue -Name 'PYTHONEXECUTABLE' -Value $oldPythonExecutable
    Set-ProcessEnvironmentValue -Name 'HERMES_TEST_INVENTORY_RUNTIME' -Value $oldInventoryFixture
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
