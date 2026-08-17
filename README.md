# Hermes Agent Windows & WSL Skills: Path Routing and Python Runtime Selection

[![Validation](https://github.com/CorsenAI/hermes-windows-runtime-skills/actions/workflows/validate.yml/badge.svg)](https://github.com/CorsenAI/hermes-windows-runtime-skills/actions/workflows/validate.yml)
[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A community-maintained Hermes Agent skill pack for deterministic path routing
across native Windows, Git Bash/MSYS, and WSL, plus fail-closed selection of an
already-installed Python interpreter. It helps agents identify execution
domains and runtime ownership without installing Python, changing dependencies,
or rewriting project files.

Community-maintained; not affiliated with or endorsed by Nous Research.

## Included Hermes skills

| Skill | Purpose | Install it when |
|---|---|---|
| [`windows-wsl-file-navigation`](skills/windows-wsl-file-navigation/) | Routes file operations using the path syntax required by the consuming process. | Windows, Git Bash/MSYS, WSL, or Hermes file tools disagree about a path. |
| [`windows-python-runtime`](skills/windows-python-runtime/) | Selects and verifies an existing project-compatible Python interpreter. | `python`, `python3`, `py`, a virtual environment, or WSL may select the wrong runtime. |

The skills are separate because path routing and Python runtime trust are
independent problems. Install either one by itself or both together. Each skill
links to the other when a task crosses both boundaries.

## Common problems this solves

- Converting a path for the process that actually consumes it, rather than for
  the shell that launched the process.
- Distinguishing `C:/project`, `/c/project`, and `/mnt/c/project` without trial
  and error.
- Diagnosing `search_files` failures such as `os error 3` without treating a
  routing error as proof that a file is absent.
- Preventing `py`, `PATH`, an application alias, or an unrelated environment
  from silently selecting the wrong Python.
- Detecting a Windows project that contains a WSL-owned virtual environment,
  or the reverse.

## Install

Install one skill directly:

```text
hermes skills install CorsenAI/hermes-windows-runtime-skills/skills/windows-wsl-file-navigation
hermes skills install CorsenAI/hermes-windows-runtime-skills/skills/windows-python-runtime
```

Or add the repository as a Hermes community tap and install either or both
skills:

```text
hermes skills tap add CorsenAI/hermes-windows-runtime-skills
hermes skills search windows
hermes skills install CorsenAI/hermes-windows-runtime-skills/windows-wsl-file-navigation
hermes skills install CorsenAI/hermes-windows-runtime-skills/windows-python-runtime
```

Then activate a skill in a Hermes session:

```text
/windows-wsl-file-navigation
/windows-python-runtime
```

## Why these skills exist

The shell shown to an agent does not determine the path syntax accepted by the
next executable. A native Windows `rg.exe` launched from Git Bash, a Linux
program launched through `wsl.exe`, and an MSYS shell builtin can each require
a different spelling for the same file.

Python adds another independent boundary. Windows virtual environments use
`Scripts/python.exe`; POSIX virtual environments use `bin/python`; WSL has its
own runtimes; and the Windows Python launcher can select a different version
from the one a project expects. The Python skill classifies ownership before
executing a trusted candidate and keeps project imports outside strict
selection because startup hooks and module code can have side effects.

The navigation skill is instruction-only. The Python skill includes a reviewed,
test-covered PowerShell resolver for already-installed official Windows
runtimes. It authenticates the launcher and runtime before executing an
isolated identity probe; it never requests Python installation, repair, update,
or package download. Neither skill requires secrets. Both stop when evidence is
insufficient.

## Compatibility and scope

| Environment | v0.1.0 status |
|---|---|
| Hermes Agent running natively on Windows with a local terminal backend | Supported and tested |
| Hermes Agent running inside WSL on a Windows host with a local terminal backend | Supported; live WSL gate available |
| Git Bash/MSYS on Windows | Supported and tested where present |
| Plain Linux without a Windows/WSL boundary | Not applicable; use normal Linux paths |
| Docker, container, SSH, or other remote terminal backends | Outside the validated v0.1.0 scope |

Container and remote backends introduce another filesystem namespace. Stop if
`${HERMES_SKILL_DIR}`, the project root, or a required executable path is not
visible to the backend that will execute it. Full Docker host-to-container path
routing belongs in a dedicated future skill and may also require backend-aware
mapping in Hermes itself; these two skills do not guess or mask that boundary.

Current Hermes builds are supported, with a capability-gated fallback for
older or unpatched builds affected by absolute-path conversion failures in
`search_files`. The normal route is used when an absolute Windows path works.
The fallback is used only after reproducing the affected behavior. The
underlying issue was reported in
[NousResearch/hermes-agent#67629](https://github.com/NousResearch/hermes-agent/issues/67629)
and fixed upstream by
[NousResearch/hermes-agent#84378](https://github.com/NousResearch/hermes-agent/pull/84378).

## Safety properties

- Start at the narrowest user-approved root.
- Treat a missing root, a failed command, and zero matches as different states.
- Never export MSYS path-conversion overrides globally.
- Never use a project-foreign Python environment as a fallback.
- Never install packages, recreate environments, or edit files while merely
  diagnosing an execution route.
- Treat every interpreter launch as code execution. Strict selection uses
  `-I -S -B`; site-enabled prefix checks and imports require a separately
  trusted environment and task authorization.
- The resolver makes no explicit network request. Authenticode validation is
  delegated to Windows trust services, whose certificate-revocation policy may
  permit network retrieval; apply the host's required offline policy when that
  distinction matters.

## Validate

Install the pinned development dependency and run the validation suite from
PowerShell:

```text
$python = '<absolute path to an already-verified Python>'
& $python -m pip install -r requirements-dev.txt
$powerShell = [IO.Path]::Combine([Environment]::SystemDirectory, 'WindowsPowerShell', 'v1.0', 'powershell.exe')
& $powerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File tests/run.ps1 -PythonExe $python
```

On a Windows host with a pre-existing test distribution, add explicit
`-WslDistro '<name>' -WslPythonSeries '<major.minor>'` arguments to include the
live WSL and Git-Bash-to-WSL gates. The suite never installs or selects a
distribution or runtime implicitly.

The standard GitHub Actions workflow validates Windows and Ubuntu contracts,
PowerShell 7, Windows PowerShell 5.1, publication hygiene, secrets, workflow
syntax, and deterministic packaging. Live WSL is an explicit release gate
because GitHub-hosted Windows runners do not provide the required test
distribution.

For a release, first run the full suite and secret scan on a clean commit, then
create the deterministic source archive:

```text
& tests/gitleaks.ps1 -RepoRoot $PWD.Path
& tests/package.ps1 -RepoRoot $PWD.Path -OutputPath ../hermes-windows-runtime-skills-v0.1.0.zip
```

The packaging gate refuses a dirty tree or an existing output file, builds
from `HEAD` with `git archive`, rejects private or traversal entries, and
verifies that archive files exactly match `git ls-files`.

## Scope of the public-source review

No exact counterpart was identified in the official Hermes skill catalogs or
the public sources checked on 2026-08-17. This is a bounded research result,
not a claim that no similar private, deleted, or unindexed project exists.

The review covered the Hermes
[bundled](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/reference/skills-catalog.md)
and
[optional](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/reference/optional-skills-catalog.md)
catalogs plus targeted public repository searches. The closest items found
were
[Windows Path Master](https://github.com/JosiahSiegel/claude-plugin-marketplace/blob/5a1b1123b9e50aa9a66a61005ca6fe012cc7442d/plugins/windows-path-master/skills/windows-path-troubleshooting/SKILL.md),
which addresses path troubleshooting but not deterministic Python ownership,
and
[uv-package-manager](https://github.com/wshobson/agents/blob/d6837ae274c2cd817acad3fb98f193a4390a4c3e/plugins/python-development/skills/uv-package-manager/SKILL.md),
which manages environments and dependencies rather than non-installing
Windows/MSYS/WSL runtime selection.

## Maintainer

[CorsenAI](https://github.com/CorsenAI)

## License

MIT
