---
name: windows-python-runtime
description: Select the correct Python runtime on Windows and WSL.
version: 0.1.0
author: CorsenAI
license: MIT
platforms: [windows, linux]
metadata:
  hermes:
    tags: [windows, wsl, python, venv, runtime, troubleshooting]
    category: software-development
    requires_tools: [terminal, search_files, read_file]
    related_skills: [windows-wsl-file-navigation, python-debugpy, systematic-debugging]
---

# Windows Python Runtime Skill

Select a project-compatible Python interpreter across native Windows, Git
Bash/MSYS, and WSL before executing Python code. This skill diagnoses and
verifies a runtime; it does not install Python, recreate environments, or
modify project dependencies.

## When to Use

- `python`, `python3`, `py`, or a project-relative interpreter fails or opens
  an application picker.
- A repository is on a Windows drive but its virtual environment was created
  inside WSL.
- Git Bash can see `bin/python` but cannot execute its Linux symlink target.
- Several global, application-owned, Conda, Poetry, `uv`, or virtual
  environment interpreters are available.
- A task needs Python but the expected version or dependency set is unclear.
- An agent is about to use the first `python` found on `PATH` as a fallback.

## Prerequisites

- Use `search_files` and `read_file` to inspect project evidence before
  executing an interpreter.
- Use `terminal` only after the execution domain and candidate are known.
- If path routing is uncertain, activate `/windows-wsl-file-navigation` first.
- Work inside the narrowest user-approved project root.

## How to Run

1. Activate `/windows-python-runtime`.
2. State the project root and whether the intended consumer is native Windows
   or WSL.
3. Follow the procedure without running bare `python`, `python3`, or `pip`.
4. Load `references/interpreter-reference.md` only when an exact probe or
   invocation form is required.

## Quick Reference

| Project evidence | Runtime domain | Preferred invocation |
|---|---|---|
| `.venv/Scripts/python.exe` plus Windows `pyvenv.cfg` | Windows | exact `python.exe` path |
| `.venv/bin/python` plus POSIX `pyvenv.cfg` | POSIX, unresolved | identify its owning domain first |
| `bin/python` pointing to `/usr/bin/python3` | POSIX, unresolved | verify WSL, Cygwin, MSYS2, or Linux |
| No venv, version pinned by project | Matching domain | explicit pinned launcher/runtime |
| No venv and no version evidence | Unknown | stop and report candidates |

A repository stored under `C:/...` can still contain a Linux virtual
environment. Storage location does not determine executable format.

## Procedure

### 1. Identify the execution domain

Use `terminal` to distinguish native Windows, Git Bash/MSYS, WSL, and plain
Linux. Record the shell and the process domain that must execute Python.

Do not treat Git Bash as Linux. It presents POSIX-looking paths while usually
launching Windows executables. Do not treat a WSL-backed model server as proof
that the current tool runs inside WSL.

### 2. Discover project evidence without Python

Use `search_files` to look narrowly for:

- `pyvenv.cfg`;
- `Scripts/python.exe` and `bin/python`;
- `.python-version`, `runtime.txt`, `pyproject.toml`, lock files, and tool
  configuration;
- documented commands in the project README or agent instructions.

Use `read_file` for metadata. Do not use Python to discover which Python to
use, and do not scan unrelated user or application directories.

### 3. Classify each candidate

Classify the virtual environment from both layout and `pyvenv.cfg`:

- `Scripts/python.exe` and a Windows-shaped `home` indicate a Windows venv.
- `bin/python` and a POSIX-shaped `home`, such as `/usr/bin`, indicate a
  POSIX venv, but do not by themselves prove WSL.
- A `bin/python` symlink targeting `/usr/bin/python3` is POSIX-path evidence,
  not executable-format proof, even when the venv directory resides on a
  mounted Windows drive. Determine whether the owner is WSL, Cygwin, MSYS2, a
  container, remote Linux, or plain Linux before executing it.
- Conflicting or incomplete evidence is an invalid candidate until resolved.

Use creation metadata, executable format, symlink targets, project
instructions, and the active runtime domain as evidence. If a venv on a shared
Windows drive could belong to several WSL distributions, do not choose a
distribution until the project identifies the owner or a read-only probe
proves it.

Never substitute an interpreter owned by Hermes, an editor, another project,
or another agent merely because it is first on `PATH`.

### 4. Respect the project manager

If the project declares `uv`, Poetry, Conda, Hatch, PDM, Pipenv, or another
manager, follow its pinned workflow only after confirming that the manager
itself belongs to the intended Windows or WSL domain. A manager found in an
unrelated environment is not project evidence.

### 5. Select one exact interpreter

- Windows venv: invoke its exact `Scripts/python.exe` path.
- WSL venv: invoke its exact `bin/python` from the selected WSL distribution.
- Windows without a venv: list installed runtimes with the Windows launcher,
  then select an explicit version such as `py -3.11` only when the project
  requires that version. The unqualified `py -3` may change after an install.
- WSL without a venv: resolve `python3` inside the selected distribution and
  require project version evidence before use.

Do not cycle through candidates until one happens to run. A successful but
foreign interpreter is more dangerous than a clean failure.

### 6. Preflight before real work

Run a read-only probe with the exact candidate and verify:

- `sys.executable` resolves to the selected environment;
- Python major and minor version match project evidence;
- `sys.prefix` and `sys.base_prefix` have the expected relationship;
- required imports succeed without changing dependencies.

If the candidate opens an application picker, redirects to an app store,
resolves to a zero-byte placeholder, or reports an unexpected executable,
reject it immediately. Do not associate the file type or retry through the
same alias.

### 7. Execute deterministically

Keep using the verified exact interpreter for every project command. Invoke
package tooling as `<exact-interpreter> -m pip` rather than bare `pip`.

Activation is optional convenience, not proof of identity. Prefer exact paths
for automated or agent-driven commands so each call remains auditable.

### 8. Stop safely when unresolved

If no candidate matches the project evidence, report the candidates and the
missing decision. Do not install a runtime, recreate a venv, edit launcher
associations, or mutate `PATH` during diagnosis without explicit permission.

## Pitfalls

1. **Bare `python`.** Windows aliases, extensionless shadows, and foreign venvs
   can intercept it.
2. **Bare `python3`.** In Git Bash it may resolve to a Windows app alias, not
   WSL Python.
3. **Floating `py -3`.** It selects the current default Python 3 runtime, which
   can change after installation or update.
4. **POSIX layout means Git Bash.** A Linux venv must execute in Linux/WSL;
   Git Bash cannot make a Linux binary into a Windows executable.
5. **Repository drive means Windows venv.** A WSL venv may live under
   `/mnt/c/...` and still remain Linux-only.
6. **Activation proves correctness.** An activation script only changes the
   environment; verify `sys.executable` afterward.
7. **First success wins.** Imports may succeed from an unrelated application
   venv while writes and upgrades affect the wrong installation.
8. **Bare `pip`.** It may target a different interpreter from the one used to
   run the project.
9. **Automatic repair.** Recreating or upgrading a venv is a mutation, not a
   diagnostic step.
10. **Nested shell guessing.** Every PowerShell, Git Bash, and WSL boundary adds
    quoting and path-conversion risk. Use the least-layered invocation.

## Verification

- The shell and runtime domain were identified independently.
- Project metadata and environment layout agree.
- Exactly one interpreter was selected from project evidence.
- The probe confirmed `sys.executable`, version, prefixes, and imports.
- No bare `python`, `python3`, `py -3`, or `pip` fallback was used.
- No package, environment, file association, or global path was changed during
  diagnosis.
