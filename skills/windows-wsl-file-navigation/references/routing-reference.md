# Routing Reference

Load this reference only for exact path conversion, WSL invocation, or legacy
`search_files` recovery.

## Consumer Matrix

| Launcher | Consumer | Input form |
|---|---|---|
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

PowerShell:

```powershell
Get-Location
Get-Command rg.exe -All -ErrorAction SilentlyContinue
wsl.exe --list --quiet
```

Git Bash:

```bash
pwd
printf 'MSYSTEM=%s\n' "${MSYSTEM:-}"
type -a rg
file "$(command -v rg)"
```

WSL, after choosing a distribution from the discovered list:

```text
wsl.exe -d <distro> --exec /usr/bin/uname -s
```

The selected distribution name is already an explicit argument. Probe only
the fields required for the decision. Never print the full environment into a
tool log or report because it may contain secrets.

## Convert with Domain Tools

Inside Git Bash:

```bash
cygpath -u 'C:\workspace\project'
cygpath -m '/c/workspace/project'
```

Inside the selected WSL distribution:

```text
wslpath -u 'C:\workspace\project'
wslpath -w '/home/developer/project'
```

Use the tool output. Do not reproduce these conversions with string
replacement because UNC paths, mount policies, and non-default drives differ.

## Invoke WSL from Git Bash

MSYS can rewrite Linux-looking arguments before `wsl.exe` receives them. Scope
the exclusion to a single path probe:

```bash
MSYS2_ARG_CONV_EXCL='*' wsl.exe -d '<distro>' --exec /usr/bin/test -d '/mnt/c/workspace/project'
```

Do not use `export MSYS2_ARG_CONV_EXCL='*'`. Prefer the structured
`search_files` tool for search patterns. Do not interpolate untrusted text into
a terminal command; apostrophes, newlines, `$()`, `!`, and other metacharacters
can cross the Git Bash parser even when `wsl.exe` ultimately launches a direct
Linux executable.

## Invoke WSL from PowerShell

PowerShell does not require the MSYS exclusion:

```powershell
& wsl.exe -d '<distro>' --exec /usr/bin/test -d '/mnt/c/workspace/project'
```

Use the structured `search_files` tool for dynamic patterns. Use `bash -lc`
only when login initialization is required. If used, treat the command as
crossing two parsers and avoid embedding untrusted strings.

## Recover from Legacy `search_files` Conversion

1. Validate the Windows root with a native operation.
2. Try `search_files` once with `path="C:/workspace/project"`.
3. If stderr reveals `/c/...` and `os error 3`, stop retrying slash variants.
4. In `terminal`, enter the root with the Git Bash form and verify `pwd`.
5. Retry the structured `search_files` tool with `path="."`. For a fixed,
   locally-authored diagnostic pattern only, the resolved native Windows
   search executable may receive a `C:/...` path.
6. Cross-check any zero through a second route before reporting absence.

On builds where the absolute Windows path succeeds, keep using the normal
`search_files` route; do not force the legacy workaround.
