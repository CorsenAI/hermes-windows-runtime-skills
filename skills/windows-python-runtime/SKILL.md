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
modify project dependencies. Its strict selection phase never intentionally
loads project modules. The bundled global Windows resolver rejects startup path
overrides before probing; virtual-environment probes apply the route-specific
checks and trust boundaries documented in the reference.

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
- Treat every interpreter execution as a trust boundary. Do not probe a
  candidate from an untrusted repository merely because its layout looks
  correct.

## How to Run

1. Activate `/windows-python-runtime`.
2. State the project root and whether the intended consumer is native Windows
   or WSL.
3. Follow the procedure without running bare `python`, `python3`, or `pip`.
4. For the global Windows route, record the resolver path
   `${HERMES_SKILL_DIR}/scripts/resolve-python-runtime.ps1`. Hermes expands the
   token in this file to the installed skill directory; do not reconstruct it
   from a user profile or search `PATH`.
5. Load `references/interpreter-reference.md` only when an exact probe or
   invocation form is required.

## Quick Reference

| Project evidence | Runtime domain | Preferred invocation |
|---|---|---|
| `.venv/Scripts/python.exe` plus Windows `pyvenv.cfg` | Windows | exact `python.exe` path |
| `.venv/bin/python` plus POSIX `pyvenv.cfg` | POSIX, unresolved | identify its owning domain first |
| `bin/python` pointing to `/usr/bin/python3` | POSIX, unresolved | verify WSL, Cygwin, MSYS2, or Linux |
| No venv, version pinned by project | Matching domain | exact path of a confirmed installed runtime |
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

Reduce version evidence to one deterministic requirement. An exact patch pin
such as `3.11.9` maps to installed series `3.11` plus an exact patch check. An
exact variant such as `3.14t` remains distinct. A range such as
`>=3.10,<3.13`, multiple `.python-version` entries, or conflicting pins does
not select a global runtime by itself; prefer an existing project environment
or stop for an explicit choice.

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
manager, inspect its pinned workflow only after confirming that the manager
belongs to the intended Windows or WSL domain. A manager found in an unrelated
environment is not project evidence. Commands such as environment sync, run,
lock, install, or update may create files or environments; do not execute them
during runtime selection.

### 5. Select one exact interpreter

- Windows venv: invoke its exact `Scripts/python.exe` path.
- WSL venv: invoke its exact `bin/python` from the selected WSL distribution.
- Windows without a venv: resolve the exact Windows launcher executable and
  authenticate its PSF signature or official AppX identity before executing
  only its compatibility inventory operation. Prefer the unambiguous modern
  `pymanager.exe` alias over the classic `py.exe`. Require one exact installed
  tag, validate the listed interpreter, and invoke that exact path directly.
  Invoke the expanded bundled resolver recorded under **How to Run**, following
  `references/interpreter-reference.md`; never use the launcher to start the
  candidate.
- WSL without a venv: derive an exact `python<major>.<minor>` name from project
  evidence, inspect only the fixed system locations documented in the
  reference, require root ownership and non-writable group/other mode, then
  invoke only the single canonical Linux path. Never trust WSL `PATH` order.

Do not cycle through candidates until one happens to run. A successful but
foreign interpreter is more dangerous than a clean failure.

### 6. Preflight before real work

Complete non-executing ownership checks first. Then, only for an environment
the user intends to execute and has reason to trust, run the strict identity
probe with `-I -S -B` and verify:

- `sys.executable` resolves to the selected environment;
- Python major and minor version match project evidence;
- the patch version, free-threaded variant, and `32`/`64`/`arm64` architecture
  match when pinned;
- normal `site` initialization is disabled and bytecode writes are suppressed;
  claim a fully site-hook-free probe only when the route-specific startup
  override checks cover every relevant configuration path.

Before probing, neutralize both `__PYVENV_LAUNCHER__` and
`PYTHONEXECUTABLE`; `-I` alone does not guarantee that these special startup
variables cannot redirect executable or path initialization. Restore their
exact prior process state afterward.

For virtual environments created by Python before 3.14, `-S` hides the venv
prefix relationship. Prove ownership from `pyvenv.cfg`, layout, domain, and
the exact executable path instead. A later site-enabled prefix or import check
is an active readiness test: `.pth`, `sitecustomize`, and imported modules may
execute arbitrary code. Run it only after trust and task authorization, never
as part of non-mutating selection.

If the candidate opens an application picker, redirects to an app store, or
reports an unexpected executable, reject it immediately. A zero-byte file is
normally invalid, but an official Windows App Execution Alias is represented
that way; accept it only when its AppX package family, manifest alias, and
installed inventory are all proven by the bundled resolver.

### 7. Execute deterministically

Keep using the verified exact interpreter for every project command. If the
user separately authorizes dependency work, bind package tooling to that exact
interpreter rather than using a bare package command. Runtime selection itself
never installs, upgrades, syncs, locks, or recreates anything.

Repeat the route-specific neutralization of `PYTHONEXECUTABLE` and
`__PYVENV_LAUNCHER__` for later invocations. Successful selection does not
sanitize the parent process permanently, and an exact executable path alone
does not override those special variables.

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
11. **Launcher means harmless.** A Windows launcher or install manager may
    automatically install a missing runtime. Inventory only, disable automatic
    installation for that call, then execute an already-listed path directly.
12. **Manager probe means read-only.** Project managers may create an
    environment even for a run or sync command. Inspect files first and do not
    execute a manager during selection.
13. **Imports are diagnostics.** Importing a module can run startup hooks,
    project code, write files, or access the network. It is never part of the
    strict selection phase.
14. **Any `py.exe` is official.** A PATH shadow can impersonate the launcher.
    Authenticate provenance before even requesting inventory.
15. **WSL PATH means system Python.** A user-writable directory can shadow the
    real runtime. Resolve fixed system candidates and verify ownership/mode.

## Verification

- The shell and runtime domain were identified independently.
- Project metadata and environment layout agree.
- Exactly one interpreter was selected from project evidence.
- The strict probe confirmed `sys.executable`, version, and any pinned variant.
  Any site-hook-free claim is limited to routes whose startup override checks
  cover all relevant configuration paths; otherwise the WSL distribution or
  environment trust boundary is stated explicitly.
- No bare `python`, `python3`, launcher-based runtime start, or bare package
  command was used.
- The selected runtime was already present before the probe; missing and
  ambiguous inventory results stopped without installation.
- No package, environment, file association, global path, `site` hook, or
  project import was changed or intentionally executed during selection.
- Any later site-enabled prefix or import readiness test was separately
  authorized and reported as active code execution.
