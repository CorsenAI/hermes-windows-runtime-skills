# Interpreter Reference

Load this reference only after identifying the project root and intended
execution domain. Selection has two phases: non-executing ownership checks,
then a strict identity probe of one trusted candidate. Dependency imports are
not part of selection.

## Read Environment Evidence

Use `read_file` on the candidate `pyvenv.cfg`. Typical domain indicators are:

```text
# Windows-shaped
home = C:\Python311

# POSIX-shaped
home = /usr/bin
```

The standard venv layouts are `Scripts` on Windows and `bin` on POSIX. Treat a
mismatch between metadata, layout, executable target, and intended domain as
unresolved. A POSIX layout proves neither WSL ownership nor a particular WSL
distribution.

## Derive One Runtime Requirement

Use the strongest project-owned evidence. Do not turn a compatibility range
into an arbitrary global-runtime choice.

| Project evidence | Installed tag | Identity requirement |
|---|---|---|
| `3.11` | `3.11` | any installed `3.11.x` |
| `3.11.9` | `3.11` | exactly `3.11.9` |
| `3.14t` | `3.14t` | free-threaded `3.14.x` |
| `3.14t-arm64` | `3.14t-arm64` | that exact tag and series |
| `>=3.10,<3.13` only | unresolved | use an existing project environment or stop |
| several pins or selectors | ambiguous | apply documented project-manager semantics or stop |

Prerelease, vendor-specific, debug, and compound constraints are outside the
bundled Windows global resolver. Use an already-owned exact environment or
stop; do not weaken the check.

Versioned executable names such as `python3.11.exe` and free-threaded names
such as `python3.14t.exe` are valid when the trusted inventory returns them.

## Resolve a Global Windows Runtime

Use `scripts/resolve-python-runtime.ps1` from this installed skill. Before
loading this reference, copy the expanded resolver path shown in the skill's
**How to Run** section. The `${HERMES_SKILL_DIR}` token expands in `SKILL.md`,
not in reference files. Do not assume another user's profile path.

From PowerShell:

```powershell
$resolver = '<expanded resolver path copied from SKILL.md>'
$powerShellPath = [IO.Path]::Combine([Environment]::SystemDirectory, 'WindowsPowerShell', 'v1.0', 'powershell.exe')
$powerShellFile = [IO.FileInfo]::new($powerShellPath); $powerShellFile.Refresh()
if (-not $powerShellFile.Exists -or $powerShellFile.Length -le 0 -or
    ($powerShellFile.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw 'The fixed system Windows PowerShell is not a regular file.'
}
$powerShellApp = $ExecutionContext.InvokeCommand.GetCommand(
    $powerShellPath, [System.Management.Automation.CommandTypes]::Application
)
if ($null -eq $powerShellApp -or
    -not $powerShellApp.Path.Equals($powerShellPath, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The fixed system Windows PowerShell is not invokable.'
}
& $powerShellApp -NoProfile -NonInteractive -File $resolver -RequiredTag '3.11' -ExpectedVersion '3.11.9'
```

From native-Windows Hermes, whose `terminal` uses Git Bash:

This bridge assumes a trusted Bash with its standard special builtins enabled.
If a profile disabled or replaced those builtins or installed execution traps,
stop and relaunch a known exact Git Bash with `--noprofile --norc`; an in-shell
snippet cannot authenticate an already-compromised shell.

```bash
(
  POSIXLY_CORRECT=1
  case ":$SHELLOPTS:" in *:posix:*) ;; *) \exit 125;; esac
  \unset -f command builtin exec 2>/dev/null || \exit 124
  cygpath_bin=/usr/bin/cygpath.exe
  [[ -f "$cygpath_bin" && -x "$cygpath_bin" && ! -L "$cygpath_bin" ]] || \exit 2
  system_dir=$(\command "$cygpath_bin" -S) || \exit 3
  case "$system_dir" in /*) ;; *) \exit 4;; esac
  powershell_bin="$system_dir/WindowsPowerShell/v1.0/powershell.exe"
  [[ -f "$powershell_bin" && -x "$powershell_bin" && ! -L "$powershell_bin" ]] || \exit 5
  resolver=$(\command "$cygpath_bin" -w '<expanded Windows resolver path copied from SKILL.md>') || \exit 6
  \exec "$powershell_bin" -NoProfile -NonInteractive -File "$resolver" -RequiredTag '3.11' -ExpectedVersion '3.11.9'
)
```

Omit `-ExpectedVersion` only when the project pins the major/minor series but
not a patch. Successful output is JSON containing the trusted launcher, exact
inventory tag, selected path, runtime-reported executable, version, prefixes,
free-threaded state, and verified architecture.

The placeholders in these examples are data, not shell syntax. Encode an
expanded path as a literal for the current shell before substitution: double a
single quote inside a PowerShell single-quoted literal, and use a correctly
escaped ANSI-C or single-quoted literal in Git Bash. Never paste an unescaped
path into a command string; spaces, apostrophes, `$()`, backticks, and `!` must
remain ordinary characters.

The resolver deliberately supports only global runtimes that meet all of
these conditions:

1. the launcher is either the exact official `pymanager.exe` App Execution
   Alias or one canonical classic location (`%WINDIR%\py.exe` or
   `%LOCALAPPDATA%\Programs\Python\Launcher\py.exe`), with a valid Python
   Software Foundation signature and matching embedded original filename;
2. only the compatibility inventory operation `-0p` is called, with
   `PYTHON_MANAGER_AUTOMATIC_INSTALL=false` scoped and restored;
3. exactly one installed inventory row matches the required tag;
4. the returned path is drive-qualified on a local fixed disk and names a
   Python executable; UNC, device, relative, and removable paths are rejected
   before filesystem access;
5. the runtime target and matching versioned CPython core DLL are PSF-signed
   through local paths with no reparse-point component, while an AppX alias is
   also bound to its exact official target;
6. no `._pth` exists beside the invocation alias or real target, and no
   unexpected `pyvenv.cfg` exists beside either relevant executable or parent;
7. its exact path passes an isolated `-I -S -B` identity probe, including an
   architecture suffix declared by either the project requirement or the
   selected inventory tag;
8. runtime-reported `sys.executable` matches the inventoried path exactly, and
   the global prefix equals the base prefix.

The script imports required built-in modules from exact paths beneath
`$PSHOME`; it does not trust `PSModulePath` to choose implementations of the
PowerShell commands used for provenance checks.

The resolver clears and restores `__PYVENV_LAUNCHER__` and
`PYTHONEXECUTABLE` around the identity probe so those special startup variables
cannot spoof `sys.executable` or redirect path initialization before the final
identity comparison.

It prefers the unambiguous modern `pymanager.exe` command and uses classic
`py.exe` only when exactly one trusted canonical classic location remains. It
does not search `PATH`; alternate standalone or custom launcher locations stop
instead of weakening selection. A regular empty file is rejected; a zero-byte
reparse point is accepted only when its AppExecLink payload, official package
family, manifest, and target bind to the exact alias. Missing, conflicting,
malformed, unsigned, or foreign results stop without launching a runtime.

The resolver contains no network client and never calls a Python install or
update operation. Its Authenticode decision is delegated to Windows trust
services; certificate-chain and revocation behavior therefore follows the
host policy and can include network retrieval unless Windows is configured for
cache-only validation. Do not describe the resolver as unconditionally
air-gapped.

The Python Install Manager retains `-0p` for compatibility. Inventory does not
install a runtime, and the resolver never asks the launcher to execute, repair,
or acquire one. Never use the launcher to start the candidate. Do not replace
the resolver with bare `py`, `python`,
`pymanager`, `list`, `exec`, or trial-and-error version launches.

## Invoke an Exact Windows Virtual Environment

First prove ownership without executing it: inspect `pyvenv.cfg`, confirm the
Windows layout, ensure the exact `Scripts/python.exe` is inside the approved
environment, and reject links or contradictory metadata. Only then run the
strict identity probe. Set `$baseHome` from the already-validated `home` value
in `pyvenv.cfg`; do not discover it by running Python. CPython `._pth` files can
override `-S`, so reject them beside both the venv executable and its trusted
base runtime before probing:

The compact example below verifies an exact executable and a major/minor
series. If project evidence also pins a patch, free-threaded variant, or
architecture, add those explicit identity fields and checks or stop; do not
claim the extra pin was verified by this series-only example.

```powershell
$pythonPath = 'C:/workspace/project/.venv/Scripts/python.exe'
$baseHome = 'C:/trusted/base-python'
$requiredSeries = '3.11'
$pythonFile = [IO.FileInfo]::new($pythonPath); $pythonFile.Refresh()
if (-not $pythonFile.Exists -or $pythonFile.Length -le 0 -or
    ($pythonFile.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw 'The exact venv executable is not a regular file.'
}
$scriptsDirectory = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($pythonPath))
foreach ($startupDirectory in @($scriptsDirectory, [IO.Path]::GetFullPath($baseHome))) {
    if ([IO.Directory]::EnumerateFiles($startupDirectory, '*._pth', [IO.SearchOption]::TopDirectoryOnly).GetEnumerator().MoveNext()) {
        throw 'A ._pth startup override makes the strict probe unsafe.'
    }
}
if ([IO.File]::Exists([IO.Path]::Combine($scriptsDirectory, 'pyvenv.cfg')) -or
    [IO.File]::Exists([IO.Path]::Combine([IO.Path]::GetFullPath($baseHome), 'pyvenv.cfg'))) {
    throw 'An unexpected secondary pyvenv.cfg makes ownership ambiguous.'
}
$pythonApp = $ExecutionContext.InvokeCommand.GetCommand(
    $pythonPath, [System.Management.Automation.CommandTypes]::Application
)
if ($null -eq $pythonApp -or
    -not $pythonApp.Path.Equals([IO.Path]::GetFullPath($pythonPath), [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The exact venv executable is not invokable.'
}
$probeCode = "import sys; print(sys.executable); print('%d.%d.%d' % sys.version_info[:3])"
$startupSettings = @('__PYVENV_LAUNCHER__', 'PYTHONEXECUTABLE')
$oldStartupValues = @{}
try {
    foreach ($setting in $startupSettings) {
        $oldStartupValues[$setting] = [Environment]::GetEnvironmentVariable($setting, 'Process')
        [Environment]::SetEnvironmentVariable($setting, [System.Management.Automation.Language.NullString]::Value, 'Process')
    }
    $identity = @(& $pythonApp -I -S -B -c $probeCode)
    $probeExit = $LASTEXITCODE
}
finally {
    foreach ($setting in $startupSettings) {
        $restore = if ($null -eq $oldStartupValues[$setting]) { [System.Management.Automation.Language.NullString]::Value } else { $oldStartupValues[$setting] }
        [Environment]::SetEnvironmentVariable($setting, $restore, 'Process')
    }
}
if ($probeExit -ne 0 -or $identity.Count -ne 2) { throw 'Venv identity probe failed.' }
$selected = [IO.Path]::GetFullPath($pythonPath)
$reported = [IO.Path]::GetFullPath($identity[0])
if (-not $selected.Equals($reported, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The venv reported a different executable.'
}
if ($identity[1] -notmatch ('^' + [regex]::Escape($requiredSeries) + '\.\d+$')) {
    throw 'The venv version does not match project evidence.'
}
```

`-I` ignores user-site packages and Python environment variables, `-S` skips
normal `site` initialization, and `-B` prevents bytecode writes. On Python
before 3.14, `-S` makes `sys.prefix` look like the base installation because
venv prefix initialization still occurred in `site`. Do not remove `-S` just
to make the prefix check pass during strict selection.

## Invoke an Exact WSL Virtual Environment

List distributions without guessing:

```powershell
$wslPath = [IO.Path]::Combine([Environment]::SystemDirectory, 'wsl.exe')
$wslFile = [IO.FileInfo]::new($wslPath); $wslFile.Refresh()
if (-not $wslFile.Exists -or $wslFile.Length -le 0 -or
    ($wslFile.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw 'The fixed system wsl.exe is not a regular file.'
}
$wslApp = $ExecutionContext.InvokeCommand.GetCommand(
    $wslPath, [System.Management.Automation.CommandTypes]::Application
)
if ($null -eq $wslApp -or
    -not $wslApp.Path.Equals($wslPath, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The fixed system wsl.exe is not invokable.'
}
$oldWslEnv = [Environment]::GetEnvironmentVariable('WSLENV', 'Process')
try {
    [Environment]::SetEnvironmentVariable('WSLENV', '', 'Process')
    & $wslApp --list --quiet
}
finally {
    $restore = if ($null -eq $oldWslEnv) { [System.Management.Automation.Language.NullString]::Value } else { $oldWslEnv }
    [Environment]::SetEnvironmentVariable('WSLENV', $restore, 'Process')
}
```

Select a distribution only from project evidence or a unique proven owner.
Then invoke the exact Linux interpreter from PowerShell. These compact examples
are series-only. If the project pins a patch, free-threaded variant, or process
architecture, add an evidence-specific check or stop rather than weakening the
pin.

```powershell
$venvPython = '/mnt/c/workspace/project/.venv/bin/python'
$requiredSeries = '3.12'
$identityCode = "import sys; print(sys.executable); print('%d.%d.%d' % sys.version_info[:3])"
$oldWslEnv = [Environment]::GetEnvironmentVariable('WSLENV', 'Process')
try {
    [Environment]::SetEnvironmentVariable('WSLENV', '', 'Process')
    & $wslApp -d '<distro>' --exec /usr/bin/test '!' -e "${venvPython}._pth"
    if ($LASTEXITCODE -ne 0) { throw 'A WSL venv ._pth startup override makes the strict probe unsafe.' }
    $identity = @(& $wslApp -d '<distro>' --exec /usr/bin/env -u PYTHONEXECUTABLE -u __PYVENV_LAUNCHER__ $venvPython -I -S -B -c $identityCode)
    if ($LASTEXITCODE -ne 0 -or $identity.Count -ne 2 -or $identity[0] -ne $venvPython) {
        throw 'The WSL venv reported a different executable.'
    }
    if ($identity[1] -notmatch ('^' + [regex]::Escape($requiredSeries) + '\.\d+$')) {
        throw 'The WSL venv version does not match project evidence.'
    }
}
finally {
    $restore = if ($null -eq $oldWslEnv) { [System.Management.Automation.Language.NullString]::Value } else { $oldWslEnv }
    [Environment]::SetEnvironmentVariable('WSLENV', $restore, 'Process')
}
```

From Git Bash, scope both MSYS exclusions to the one call:

```bash
(
  POSIXLY_CORRECT=1
  case ":$SHELLOPTS:" in *:posix:*) ;; *) \exit 125;; esac
  \unset -f command builtin exec 2>/dev/null || \exit 124
  cygpath_bin=/usr/bin/cygpath.exe
  [[ -f "$cygpath_bin" && -x "$cygpath_bin" && ! -L "$cygpath_bin" ]] || \exit 2
  system_dir=$(\command "$cygpath_bin" -S) || \exit 3
  case "$system_dir" in /*) ;; *) \exit 4;; esac
  wsl_bin="$system_dir/wsl.exe"
  [[ -f "$wsl_bin" && -x "$wsl_bin" && ! -L "$wsl_bin" ]] || \exit 5
  WSLENV= MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'
  \export WSLENV MSYS_NO_PATHCONV MSYS2_ARG_CONV_EXCL || \exit 123
  venv_python='/mnt/c/workspace/project/.venv/bin/python'
  required_series='3.12'
  \command "$wsl_bin" -d '<distro>' --exec /usr/bin/test '!' -e "${venv_python}._pth" || \exit 6
  identity=$(\command "$wsl_bin" -d '<distro>' --exec /usr/bin/env -u PYTHONEXECUTABLE -u __PYVENV_LAUNCHER__ "$venv_python" -I -S -B -c 'import sys; print(sys.executable); print("%d.%d.%d" % sys.version_info[:3])') || \exit 6
  identity=${identity//$'\r'/}
  [[ "$identity" == *$'\n'* && "${identity#*$'\n'}" != *$'\n'* ]] || \exit 7
  reported_path=${identity%%$'\n'*}
  reported_version=${identity#*$'\n'}
  [[ "$reported_path" == "$venv_python" ]] || \exit 7
  version_prefix=${required_series//./\\.}
  [[ "$reported_version" =~ ^${version_prefix}\.[0-9]+$ ]] || \exit 8
)
```

Never export those exclusions globally.

Under the trusted-shell prerequisite above, the examples scope `WSLENV` to an
empty value so Windows-side variables such as `LD_PRELOAD` are not forwarded
into the Linux loader. This does not sanitize the selected distribution's own
system configuration; its root-owned loader, `/usr/bin` programs, and package
state remain an explicit trust boundary.

## Resolve WSL Without a Virtual Environment

This route requires one selected distribution and an exact major/minor series.
Do not use it for a version range. Inspect only `/usr/bin/python<series>` and
`/usr/local/bin/python<series>`; never use WSL `PATH`, `command -v`, or a bare
interpreter. Require one canonical, root-owned regular file whose group and
other write bits are clear. This route is series-only: if the project pins an
exact patch, free-threaded variant, or process architecture, stop and use an
owned environment or a probe that verifies that additional evidence.

From PowerShell:

```powershell
$distro = '<project-owned-distro>'
$requiredSeries = '3.12'
$wslPath = [IO.Path]::Combine([Environment]::SystemDirectory, 'wsl.exe')
$wslFile = [IO.FileInfo]::new($wslPath); $wslFile.Refresh()
if (-not $wslFile.Exists -or $wslFile.Length -le 0 -or
    ($wslFile.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw 'The fixed system wsl.exe is not a regular file.'
}
$wslApp = $ExecutionContext.InvokeCommand.GetCommand(
    $wslPath, [System.Management.Automation.CommandTypes]::Application
)
if ($null -eq $wslApp -or
    -not $wslApp.Path.Equals($wslPath, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The fixed system wsl.exe is not invokable.'
}
$oldWslEnv = [Environment]::GetEnvironmentVariable('WSLENV', 'Process')
try {
  [Environment]::SetEnvironmentVariable('WSLENV', '', 'Process')
  if ($requiredSeries -notmatch '^\d+\.\d+$') { throw 'An exact Python series is required.' }
  $runtimeName = "python$requiredSeries"
  $resolved = [System.Collections.Generic.List[string]]::new()
  foreach ($candidate in @("/usr/bin/$runtimeName", "/usr/local/bin/$runtimeName")) {
    & $wslApp -d $distro --exec /usr/bin/test -e $candidate
    if ($LASTEXITCODE -eq 1) { continue }
    if ($LASTEXITCODE -ne 0) { throw 'WSL candidate existence check failed.' }
    $canonical = @(& $wslApp -d $distro --exec /usr/bin/readlink -f -- $candidate)
    if ($LASTEXITCODE -ne 0 -or $canonical.Count -ne 1 -or $canonical[0] -notmatch '^/[A-Za-z0-9._/+:-]+$') {
        throw 'WSL candidate canonicalization failed.'
    }
    & $wslApp -d $distro --exec /usr/bin/test -f $canonical[0]
    if ($LASTEXITCODE -ne 0) { throw 'WSL candidate is not a regular file.' }
    & $wslApp -d $distro --exec /usr/bin/test -x $canonical[0]
    if ($LASTEXITCODE -ne 0) { throw 'WSL candidate is not executable.' }
    $metadata = @(& $wslApp -d $distro --exec /usr/bin/stat -c '%u:%a' -- $canonical[0])
    if ($LASTEXITCODE -ne 0 -or $metadata.Count -ne 1 -or $metadata[0] -notmatch '^0:(?<mode>[0-7]{3})$') {
        throw 'WSL candidate is not root-owned or has special mode bits.'
    }
    $mode = $Matches['mode']
    if ($mode.Substring($mode.Length - 2) -match '[2367]') { throw 'WSL candidate is group/other writable.' }
    if (-not $resolved.Contains($canonical[0])) { $resolved.Add($canonical[0]) }
  }
  if ($resolved.Count -ne 1) { throw 'The installed WSL runtime was absent or ambiguous.' }
  $pythonPath = $resolved[0]
  & $wslApp -d $distro --exec /usr/bin/test '!' -e "${pythonPath}._pth"
  if ($LASTEXITCODE -ne 0) { throw 'A WSL ._pth startup override makes the strict probe unsafe.' }
  $identityCode = "import sys; print(sys.executable); print('%d.%d.%d' % sys.version_info[:3])"
  $identity = @(& $wslApp -d $distro --exec /usr/bin/env -u PYTHONEXECUTABLE -u __PYVENV_LAUNCHER__ $pythonPath -I -S -B -c $identityCode)
  if ($LASTEXITCODE -ne 0 -or $identity.Count -ne 2) { throw 'WSL identity probe failed.' }
  if ($identity[0] -ne $pythonPath) { throw 'WSL runtime reported a different executable.' }
  if ($identity[1] -notmatch ('^' + [regex]::Escape($requiredSeries) + '\.\d+$')) {
    throw 'WSL runtime series does not match project evidence.'
  }
}
finally {
  $restore = if ($null -eq $oldWslEnv) { [System.Management.Automation.Language.NullString]::Value } else { $oldWslEnv }
  [Environment]::SetEnvironmentVariable('WSLENV', $restore, 'Process')
}
```

From Git Bash, keep the fixed shell program single-quoted and pass the safe
runtime name as positional data:

```bash
(
  POSIXLY_CORRECT=1
  case ":$SHELLOPTS:" in *:posix:*) ;; *) \exit 125;; esac
  \unset -f command builtin exec 2>/dev/null || \exit 124
  distro='<project-owned-distro>'
  required_series='3.12'
  cygpath_bin=/usr/bin/cygpath.exe
  [[ -f "$cygpath_bin" && -x "$cygpath_bin" && ! -L "$cygpath_bin" ]] || \exit 2
  system_dir=$(\command "$cygpath_bin" -S) || \exit 3
  case "$system_dir" in /*) ;; *) \exit 4;; esac
  wsl_bin="$system_dir/wsl.exe"
  [[ -f "$wsl_bin" && -x "$wsl_bin" && ! -L "$wsl_bin" ]] || \exit 5
  WSLENV= MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'
  \export WSLENV MSYS_NO_PATHCONV MSYS2_ARG_CONV_EXCL || \exit 123
  case "$required_series" in
    ''|*[!0-9.]*|.*|*.|*.*.*) \exit 2 ;;
    *.*) ;;
    *) \exit 2 ;;
  esac
  runtime_name="python$required_series"
  resolved=()
  for candidate in "/usr/bin/$runtime_name" "/usr/local/bin/$runtime_name"; do
    if \command "$wsl_bin" -d "$distro" --exec /usr/bin/test -e "$candidate"; then
      python_path=$(\command "$wsl_bin" -d "$distro" --exec /usr/bin/readlink -f -- "$candidate") || \exit
    python_path=${python_path%$'\r'}
      case "$python_path" in /*) ;; *) \exit 14;; esac
      \command "$wsl_bin" -d "$distro" --exec /usr/bin/test -f "$python_path" || \exit 15
      metadata=$(\command "$wsl_bin" -d "$distro" --exec /usr/bin/stat -c '%u:%a' -- "$python_path") || \exit
    metadata=${metadata%$'\r'}
      [[ "$metadata" =~ ^0:([0-7]{3})$ ]] || \exit 15
      mode=${BASH_REMATCH[1]}
      [[ ${mode: -2:1} != [2367] && ${mode: -1} != [2367] ]] || \exit 16
      \command "$wsl_bin" -d "$distro" --exec /usr/bin/test -x "$python_path" || \exit
    [[ " ${resolved[*]} " == *" $python_path "* ]] || resolved+=("$python_path")
    elif [[ $? -ne 1 ]]; then
      \exit 17
    fi
  done
  [[ ${#resolved[@]} -eq 1 ]] || \exit 18
  python_path=${resolved[0]}
  \command "$wsl_bin" -d "$distro" --exec /usr/bin/test '!' -e "${python_path}._pth" || \exit 19
  identity=$(\command "$wsl_bin" -d "$distro" --exec /usr/bin/env -u PYTHONEXECUTABLE -u __PYVENV_LAUNCHER__ "$python_path" -I -S -B -c 'import sys; print(sys.executable); print("%d.%d.%d" % sys.version_info[:3])') || \exit 19
  identity=${identity//$'\r'/}
  [[ "$identity" == *$'\n'* && "${identity#*$'\n'}" != *$'\n'* ]] || \exit 20
  reported_path=${identity%%$'\n'*}
  reported_version=${identity#*$'\n'}
  [[ "$reported_path" == "$python_path" ]] || \exit 20
  version_prefix=${required_series//./\\.}
  [[ "$reported_version" =~ ^${version_prefix}\.[0-9]+$ ]] || \exit 21
)
```

If the fixed system candidates, `readlink`, `stat`, exact executable identity,
adjacent `._pth` rejection, or version proof are unavailable, stop; do not
search user `PATH`, install a package, or fall back to `python3`. The selected
distribution's root-owned shared library and loader configuration remain a
trust boundary; these examples do not claim to authenticate the distribution.

## Active Readiness Checks

After strict selection, a user-authorized task may require normal site startup
or imports. These are active code execution, not read-only probes: `.pth`
lines, `sitecustomize`, and imported modules may write files, launch processes,
or access the network.

Repeat the Windows save/clear/restore wrapper, or use WSL's exact
`/usr/bin/env` wrapper with both `-u PYTHONEXECUTABLE` and
`-u __PYVENV_LAUNCHER__`, for every later invocation. The selection probe
restores the parent environment; it does not make future exact-path launches
immune to those special startup variables.

For a trusted environment only, a separate readiness check can use its exact
interpreter:

```text
<exact-interpreter> -I -B -c "import sys, <required-module>; print(sys.executable); print(sys.prefix); print(sys.base_prefix)"
```

An import failure is evidence that the chosen environment does not currently
satisfy the task. It is not permission to install a package, run a manager,
or borrow another environment.

## Inspect POSIX Candidates Without Executing Them

Inspect a POSIX layout inside every plausible owning domain:

```text
file -L '<candidate>'
readlink '<candidate>'
readlink -f '<candidate>'
test -e '<candidate>'
test -x '<candidate>'
```

Use the selected WSL distribution for WSL evidence and Git Bash only for MSYS
evidence. `file -L` may return success while saying its target cannot be
opened. Require the reported type plus `test -e`, and require `test -x` before
execution. A Git Bash result never proves WSL ownership. If more than one WSL
distribution remains plausible, stop rather than selecting the first.

## Decision Table

| Observation | Interpretation | Action |
|---|---|---|
| App picker or Store redirect | unproven alias | reject |
| Windows venv evidence agrees | possible owned environment | strict exact-path probe |
| `bin/python` targets `/usr/bin/...` | POSIX, unresolved | prove owner or stop |
| Resolver returns one exact Windows runtime | installed trusted match | use `SelectedPath` |
| Resolver rejects launcher/runtime | provenance failed | stop; do not bypass |
| Inventory lacks the required tag | no safe installed match | stop without installation |
| Version range is the only evidence | global choice is ambiguous | use owned venv or request choice |
| Import works only in another app's virtual environment | runtime belongs to another app | do not borrow it |

## Authoritative References

- [Using Python on Windows](https://docs.python.org/3/using/windows.html)
- [Python virtual environments](https://docs.python.org/3/library/venv.html)
- [Python path initialization](https://docs.python.org/3/library/sys_path_init.html)
- [Python site initialization](https://docs.python.org/3/library/site.html)
