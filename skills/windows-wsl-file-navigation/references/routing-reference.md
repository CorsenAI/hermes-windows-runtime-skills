# Routing Reference

Load this reference only for exact path conversion, WSL invocation, or legacy
`search_files` recovery.

## Consumer Matrix

| Launcher | Consumer | Input form |
|---|---|---|
| Hermes on native Windows | `search_files` or `read_file` | `C:/workspace/project` |
| Hermes inside WSL | `search_files` or `read_file` | `/mnt/c/workspace/project` |
| Hermes inside WSL | WSL-owned file | `/home/developer/project` |
| PowerShell or CMD | Windows executable | `C:/workspace/project` |
| Git Bash | MSYS builtin | `/c/workspace/project` |
| Git Bash | Windows executable | `C:/workspace/project` |
| PowerShell | Linux executable through WSL | `/mnt/c/workspace/project` |
| Git Bash | Linux executable through WSL | `/mnt/c/workspace/project`, with per-call MSYS exclusion |
| Windows file API | WSL filesystem | `\\wsl.localhost\<distro>\home\developer` |

Use WSL UNC for Linux-owned files. If the target is a Windows file visible in
WSL under `/mnt/<drive>`, address it directly with its Windows path instead of
re-exporting it through `\\wsl.localhost\<distro>\mnt\...`.

## Detect Before Converting

These Git Bash snippets assume a trusted Bash with its standard special
builtins enabled. If a profile has disabled or replaced those builtins, or has
installed execution traps, stop and relaunch a known exact Git Bash with
`--noprofile --norc`; do not try to recover inside the altered shell.

PowerShell:

```powershell
Get-Location
Get-Command rg.exe -All -ErrorAction SilentlyContinue
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

Git Bash:

```bash
pwd
printf 'MSYSTEM=%s\n' "${MSYSTEM:-}"
type -a rg
file "$(command -v rg)"
```

WSL from PowerShell, after choosing a distribution from the discovered list:

```powershell
$oldWslEnv = [Environment]::GetEnvironmentVariable('WSLENV', 'Process')
try {
    [Environment]::SetEnvironmentVariable('WSLENV', '', 'Process')
    & $wslApp -d '<distro>' --exec /usr/bin/uname -s
}
finally {
    $restore = if ($null -eq $oldWslEnv) { [System.Management.Automation.Language.NullString]::Value } else { $oldWslEnv }
    [Environment]::SetEnvironmentVariable('WSLENV', $restore, 'Process')
}
```

WSL from Git Bash requires a per-call conversion exclusion:

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
  \exec "$wsl_bin" -d '<distro>' --exec /usr/bin/uname -s
)
```

The selected distribution name is already an explicit argument. Probe only
the fields required for the decision. Never print the full environment into a
tool log or report because it may contain secrets.

## Convert with Domain Tools

Inside Git Bash:

```bash
(
  POSIXLY_CORRECT=1
  case ":$SHELLOPTS:" in *:posix:*) ;; *) \exit 125;; esac
  \unset -f command builtin exec 2>/dev/null || \exit 124
  cygpath_bin=/usr/bin/cygpath.exe
  [[ -f "$cygpath_bin" && -x "$cygpath_bin" && ! -L "$cygpath_bin" ]] || \exit 2
  \command "$cygpath_bin" -u 'C:\workspace\project'
  \command "$cygpath_bin" -m '/c/workspace/project'
)
```

Inside the selected WSL distribution:

```text
/usr/bin/wslpath -u 'C:\workspace\project'
/usr/bin/wslpath -w '/home/developer/project'
```

Use the tool output. Do not reproduce these conversions with string
replacement because UNC paths, mount policies, and non-default drives differ.

## Invoke WSL from Git Bash

MSYS can rewrite Linux-looking arguments before `wsl.exe` receives them. Scope
the exclusion to a single path probe:

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
  \exec "$wsl_bin" -d '<distro>' --exec /usr/bin/test -d '/mnt/c/workspace/project'
)
```

Do not export either exclusion. Prefer the structured
`search_files` tool for search patterns. Do not interpolate untrusted text into
a terminal command; apostrophes, newlines, `$()`, `!`, and other metacharacters
can cross the Git Bash parser even when `wsl.exe` ultimately launches a direct
Linux executable.

## Invoke WSL from PowerShell

PowerShell does not require the MSYS exclusion:

```powershell
$oldWslEnv = [Environment]::GetEnvironmentVariable('WSLENV', 'Process')
try {
    [Environment]::SetEnvironmentVariable('WSLENV', '', 'Process')
    & $wslApp -d '<distro>' --exec /usr/bin/test -d '/mnt/c/workspace/project'
}
finally {
    $restore = if ($null -eq $oldWslEnv) { [System.Management.Automation.Language.NullString]::Value } else { $oldWslEnv }
    [Environment]::SetEnvironmentVariable('WSLENV', $restore, 'Process')
}
```

Use the structured `search_files` tool for dynamic patterns. Use `bash -lc`
only when login initialization is required. If used, treat the command as
crossing two parsers and avoid embedding untrusted strings.

Under the trusted-shell prerequisite above, scoping `WSLENV` to an empty value
prevents Windows-side variables such as `LD_PRELOAD` from being forwarded into
the Linux loader. It does not sanitize the selected distribution's own loader,
`/usr/bin` programs, or package state; those remain an explicit trust boundary.

## Recover from Legacy `search_files` Conversion

This fallback is only for native Windows Hermes backends. A WSL backend
must use its backend-visible `/mnt/...` or POSIX path instead.

1. Validate that Hermes file tools are running on native Windows, then validate
   the Windows root with a native operation.
2. Try `search_files` once with `path="C:/workspace/project"`.
3. If stderr reveals `/c/...` and `os error 3`, stop retrying slash variants.
4. In `terminal`, enter the root with the Git Bash form and verify `pwd`.
5. Retry the structured `search_files` tool with `path="."`. For a fixed,
   locally-authored diagnostic pattern only, the resolved native Windows
   search executable may receive a `C:/...` path.
6. Cross-check any zero through a second route before reporting absence.

On builds where the absolute Windows path succeeds, keep using the normal
`search_files` route; do not force the legacy workaround.

## Protect Leading-Dash Search Values

Some Hermes wrappers construct the underlying search command without `-e`
before the regex or `--` before the root. Quoting protects the shell but does
not stop the search executable from interpreting a leading `-` as an option.

- Do not pass a leading-dash regex verbatim to `search_files`.
- Preserve regex semantics by wrapping the entire validated expression in a
  noncapturing group: `- Use` becomes `(?:- Use)`.
- For a literal search, regex-escape all metacharacters first, then wrap the
  result in `(?:...)`.
- Normalize a relative root such as `-fixtures` to `./-fixtures`, or use its
  absolute path in the backend's domain.
- Treat unexpected help/version output as command failure, never as a clean
  zero or match.

Do not solve this by interpolating the user value into `terminal`. A core
implementation can use explicit pattern and option terminators, but the skill
must remain safe on builds that do not.

## Validate POSIX Candidates

When a path may be a symlink or executable, probe it in every plausible POSIX
domain rather than trusting one successful-looking command:

```text
file -L '<candidate>'
readlink '<candidate>'
readlink -f '<candidate>'
test -e '<candidate>'
test -x '<candidate>'
```

Run these through the chosen WSL distribution for WSL evidence and inside Git
Bash only for MSYS evidence. `file -L` may return success while describing an
unreadable target, and `readlink -f` alone does not prove that the resolved
target is accessible or executable. Require the output plus `test -e`; require
`test -x` before execution. A Git Bash result never proves WSL ownership.

## Authoritative References

- [Hermes Agent on native Windows](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/windows-native.md)
- [Hermes Agent Windows and WSL2 quickstart](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/windows-wsl-quickstart.md)
- [Hermes issue #67629](https://github.com/NousResearch/hermes-agent/issues/67629)
- [Hermes fix #84378](https://github.com/NousResearch/hermes-agent/pull/84378)
