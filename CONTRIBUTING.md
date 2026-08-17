# Contributing

Contributions are welcome when they keep the skills deterministic,
non-destructive, and narrowly scoped to Windows, Git Bash/MSYS, and WSL runtime
boundaries.

## Before opening an issue

- Search existing issues and pull requests.
- Reproduce the behavior on a supported environment where possible.
- Use the security process in [SECURITY.md](SECURITY.md) for vulnerabilities.
- Report Hermes Agent defects upstream when the problem is not caused by this
  repository.

## Development setup

Use an already-verified Python interpreter. From PowerShell:

```powershell
$python = '<absolute path to an already-verified Python>'
& $python -m pip install -r requirements-dev.txt
$powerShell = [IO.Path]::Combine(
    [Environment]::SystemDirectory,
    'WindowsPowerShell',
    'v1.0',
    'powershell.exe'
)
& $powerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File tests/run.ps1 -PythonExe $python
```

On a Windows host with a pre-existing WSL test distribution, pass the explicit
`-WslDistro` and `-WslPythonSeries` arguments described in the README. The test
suite must not install a distribution or runtime implicitly.

## Change guidelines

- Keep path routing and Python runtime trust as separate decisions.
- Prefer read-only probes and fail closed when evidence is ambiguous.
- Do not add commands that install Python, packages, WSL distributions, or
  system tools during diagnosis.
- Do not use a project-foreign interpreter as a fallback.
- Do not export MSYS path-conversion overrides globally.
- Keep `SKILL.md` concise and place detailed command references under
  `references/`.
- Add or update a regression test for behavioral changes.
- Keep third-party GitHub Actions and downloaded validation tools pinned.
- Do not commit generated archives, credentials, machine-specific paths, or
  private test data.

## Pull requests

Create a focused branch such as `fix/<topic>`, `docs/<topic>`, or
`test/<topic>`. A pull request should contain:

- a concise explanation of the problem and the chosen boundary;
- the supported environments affected by the change;
- the commands or CI jobs used for validation;
- any security or compatibility trade-offs;
- documentation updates when user-visible behavior changes.

Keep unrelated refactoring out of the same pull request. Release versions are
changed only as part of an explicit release.

## Commit messages

Use a short imperative subject that describes the repository change. Add a
body only when the reason or security boundary is not clear from the diff.

## License

By contributing, you agree that your contribution is licensed under the MIT
License used by this repository.
