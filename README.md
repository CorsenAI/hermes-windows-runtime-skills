# Hermes Windows Runtime Skills

Two focused Hermes Agent skills for projects that cross native Windows, Git
Bash/MSYS, and WSL boundaries:

- `windows-wsl-file-navigation` routes file reads and searches to the correct
  path domain.
- `windows-python-runtime` selects the project interpreter without falling
  through to an unrelated Python installation or execution alias.

Both skills are instruction-only at runtime. They install no software, make no
network requests, and require no secrets.

## Install

Install one skill directly:

```text
hermes skills install CorsenAI/hermes-windows-runtime-skills/skills/windows-wsl-file-navigation
hermes skills install CorsenAI/hermes-windows-runtime-skills/skills/windows-python-runtime
```

Or add the repository as a community tap:

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
from the one a project expects. The Python skill classifies the environment
before executing anything.

## Compatibility

- Hermes Agent running natively on Windows.
- Hermes Agent running inside WSL on a Windows host.
- Git Bash/MSYS when present.
- Current Hermes builds and older builds affected by absolute-path conversion
  failures in `search_files`.

The path skill documents a capability probe instead of assuming a Hermes
version. The underlying absolute-path issue was reported in
[NousResearch/hermes-agent#67629](https://github.com/NousResearch/hermes-agent/issues/67629)
and fixed upstream by
[NousResearch/hermes-agent#84378](https://github.com/NousResearch/hermes-agent/pull/84378).

## Safety

- Start at the narrowest user-approved root.
- Treat a missing root, a failed command, and zero matches as different states.
- Never export MSYS path-conversion overrides globally.
- Never use a project-foreign Python environment as a fallback.
- Never install packages, recreate environments, or edit files while merely
  diagnosing an execution route.

## Validate

Run the dependency-free validation suite from PowerShell:

```text
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1
```

The suite checks skill metadata, required procedures, publication hygiene, and
the absence of machine-specific paths or internal transcript markers.

## Maintainer

[CorsenAI](https://github.com/CorsenAI)

## License

MIT
