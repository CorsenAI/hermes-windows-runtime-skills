# Interpreter Reference

Load this reference only after the project root and intended execution domain
have been identified.

## Read the Environment Evidence

Use `read_file` on the candidate `pyvenv.cfg`. Typical domain indicators are:

```text
# Windows-shaped
home = C:\Python311

# POSIX-shaped
home = /usr/bin
```

The standard venv layouts are `Scripts` on Windows and `bin` on POSIX. Treat a
mismatch between metadata, layout, and executable target as unresolved.

## Inspect Windows Runtimes Without Launching One

From PowerShell, first resolve what `py` and any Python aliases actually are:

```powershell
Get-Command py.exe -All -ErrorAction SilentlyContinue
Get-Command python -All -ErrorAction SilentlyContinue
Get-Command python3 -All -ErrorAction SilentlyContinue
```

If the official Windows launcher or Python install manager is present, resolve
its exact executable and use the compatibility listing form. It does not start
the default interpreter:

```powershell
$launcher = Get-Command py.exe -ErrorAction Stop
& $launcher.Source -0p
```

The current Python install manager retains `-0p` for compatibility with the
classic launcher. Do not use `py` alone as a probe: it starts whichever runtime
is currently the default. Do not pass a bare word such as `list` to an
unclassified launcher; the classic launcher can treat it as a script name and
start Python.

Select a version only when project evidence supports it:

```powershell
py -3.11 -c "import sys; print(sys.executable); print(sys.version_info[:2])"
```

## Invoke an Exact Windows Virtual Environment

Use the candidate path rather than activation or `PATH` lookup:

```powershell
& 'C:/workspace/project/.venv/Scripts/python.exe' -c "import sys; print(sys.executable); print(sys.prefix); print(sys.base_prefix)"
```

For dependency operations, bind `pip` to that same interpreter:

```powershell
& 'C:/workspace/project/.venv/Scripts/python.exe' -m pip --version
```

Do not install or upgrade anything during selection.

## Invoke an Exact WSL Virtual Environment

Discover distribution names first rather than hard-coding one:

```powershell
wsl.exe --list --quiet
```

Then invoke the Linux interpreter directly from PowerShell:

```powershell
& wsl.exe -d '<distro>' --exec '/mnt/c/workspace/project/.venv/bin/python' -c 'import sys; print(sys.executable); print(sys.prefix); print(sys.base_prefix)'
```

When the launcher is Git Bash, prevent MSYS from rewriting the Linux
arguments, but scope the override to this one command:

```bash
MSYS2_ARG_CONV_EXCL='*' wsl.exe -d '<distro>' --exec '/mnt/c/workspace/project/.venv/bin/python' -c 'import sys; print(sys.executable); print(sys.prefix); print(sys.base_prefix)'
```

Never export the exclusion globally.

## Verify Required Imports

Use the exact candidate and import only the modules required by the task:

```text
<exact-interpreter> -c "import sys, sqlite3; print(sys.executable); print(sys.version_info[:2])"
```

An import failure is evidence that the candidate does not currently satisfy
the task. It is not permission to install a package or switch to a foreign
environment.

## Decision Table

| Observation | Interpretation | Action |
|---|---|---|
| App picker or store opens | alias/association, not verified Python | reject alias |
| `Scripts/python.exe` exists | possible Windows environment | confirm `pyvenv.cfg`, then probe exact path |
| `bin/python` targets `/usr/bin/...` | POSIX, unresolved | determine its owner; stop if unproven |
| `py -3` runs a newer version | floating Windows default | use project-pinned `py -3.x` or exact environment |
| Import succeeds only in an app-owned environment | foreign environment | stop; do not borrow it |
| Version and imports match but path differs | wrong candidate | reject and report mismatch |
| No project version evidence | selection ambiguous | report candidates and request direction |

## Authoritative References

- [Python virtual environments](https://docs.python.org/3/library/venv.html)
- [Using Python on Windows](https://docs.python.org/3/using/windows.html)
