---
name: windows-wsl-file-navigation
description: Resolve file paths across Windows, Git Bash, and WSL.
version: 0.1.0
author: CorsenAI
license: MIT
platforms: [windows, linux]
metadata:
  hermes:
    tags: [windows, wsl, git-bash, msys, path-routing, path-conversion]
    category: software-development
    requires_tools: [terminal, search_files, read_file]
    related_skills: [windows-python-runtime, codebase-inspection, systematic-debugging]
---

# Windows WSL File Navigation Skill

Route file operations according to the program that consumes the path, not
merely the shell that launches it. This skill diagnoses and searches; it does
not move, delete, or rewrite user files.

## Companion Skill

This skill solves path and execution-domain routing. If the task also needs to
choose or verify a Python interpreter, install and activate the complementary
[`windows-python-runtime`](../windows-python-runtime/) skill. It treats Python
ownership and trust as a separate decision instead of assuming that a valid
path identifies the correct runtime. Install source:
`CorsenAI/hermes-windows-runtime-skills/skills/windows-python-runtime`.

## When to Use

- A path works in one of Windows, Git Bash, or WSL but fails in another.
- `search_files` reports `os error 3`, rewrites `C:/...` to `/c/...`, or returns
  an implausible zero.
- A task needs searches in both Windows and WSL.
- An agent is about to claim that a file or directory does not exist.
- The underlying search executable may be native Windows rather than
  MSYS/Linux.

## Prerequisites

- Use `terminal`, `search_files`, and `read_file`.
- Confirm where the Hermes file-tool backend runs: native Windows, WSL, plain
  Linux, or another remote environment. The desktop UI and model server
  location do not establish that backend.
- Confirm that the host is Windows or that the current Linux environment is
  WSL. On plain Linux, use normal Linux paths and stop applying Windows
  conversions from this skill.
- Treat Git Bash and WSL as different execution domains.
- Remote and container terminal backends are outside the v0.1.0 scope. If
  `${HERMES_SKILL_DIR}`, the intended root, or the required path is not visible
  from the execution backend, stop instead of guessing a host-to-backend
  mapping.
- Treat the shell interpreter itself as a trust boundary. If a Git Bash profile
  disables or replaces special builtins, injects traps, or otherwise changes
  command semantics, stop and restart a known exact Bash without profiles;
  in-shell path defenses cannot authenticate an already-compromised shell.

## How to Run

1. Activate `/windows-wsl-file-navigation`.
2. State the intended root, operation, and target environment.
3. Follow the procedure below before issuing a broad search.
4. Load `references/routing-reference.md` only when an exact conversion or
   legacy recovery command is needed.

## Quick Reference

| Consumer | Backend/domain | Example |
|---|---|---|
| Hermes file tools via native Windows | Windows | `C:/workspace/project` |
| Hermes file tools via WSL | WSL | `/mnt/c/workspace/project` |
| Hermes file tools on WSL-owned files | WSL | `/home/developer/project` |
| Native Windows executable | Windows | `C:/workspace/project` |
| Git Bash/MSYS builtin | MSYS | `/c/workspace/project` |
| Linux executable in WSL | WSL | `/mnt/c/workspace/project` |
| Windows API reading WSL files | WSL UNC | `\\wsl.localhost\<distro>\home\developer` |

`/c/...` and `/mnt/c/...` are not interchangeable. A Windows executable
launched by Git Bash should receive `C:/...`; relying on automatic MSYS
translation is fragile.

## Procedure

### 1. Fingerprint the execution domains

Use `terminal` to establish all of the following before converting anything:

- the execution backend used by `search_files` and `read_file`;
- current shell and working directory;
- whether `MSYSTEM` or `WSL_DISTRO_NAME` is present;
- the actual path and binary family of the executable that will consume the
  path;
- installed WSL distribution names when WSL is required.

Do not infer the tool domain from the GUI, shell appearance, or model server. A
model served from WSL can control native Windows tools, while a native Windows
desktop can connect to a Hermes backend running inside WSL.

### 2. Classify the path

- `C:/...` or `C:\...`: Windows-native path.
- `/c/...`: MSYS drive-shaped path.
- `/mnt/c/...`: Windows drive mounted inside WSL.
- `\\wsl.localhost\<distro>\...`: WSL file exposed to Windows.
- `/home/...` or another POSIX path: ambiguous until the executing environment
  is known; Git Bash also has a POSIX-looking root.
- Relative path: ambiguous until both the current directory and consumer are
  recorded.

Use `cygpath` only inside Git Bash and `wslpath` only inside the selected WSL
distribution. Do not convert paths with ad-hoc string replacement.

### 3. Validate the root

Check the root through the same Hermes backend or executable that will consume
the final path. Record one of four states:

1. root exists;
2. root is missing;
3. route or conversion failed;
4. required executable is unavailable.

States 2-4 do not prove that the requested file is absent.

### 4. Choose the least-layered route

- First identify the backend used by `search_files` and `read_file`. For a
  Windows-drive file, use `C:/...` only with a native Windows backend and
  `/mnt/c/...` with a WSL backend. Use `/home/...` for WSL-owned files.
- On a native Windows backend, try the normal absolute `C:/...` route once.
  Enter legacy recovery only if that capability probe reproduces the known
  conversion failure; never select it from a version guess alone.
- For WSL files, use `terminal` to invoke the chosen distribution directly.
  Prefer a direct executable call; add a login shell only when the command
  genuinely depends on login initialization.
- When Git Bash launches `wsl.exe`, scope the MSYS conversion exclusion to that
  single call. Never export it for the session.
- Keep user-supplied patterns in the structured `search_files` tool, but first
  account for wrappers that do not place an option terminator before the
  pattern. Never send a regex beginning with `-` verbatim. Wrap the complete
  valid regex in a noncapturing group, such as `(?:- Use)`; for literal text,
  regex-escape it before wrapping. If semantics cannot be preserved, stop
  instead of moving untrusted text into `terminal`.
- Normalize a relative root beginning with `-` to `./<name>` or to an absolute
  path in the consumer's domain before searching it.
- For a known WSL-owned file consumed by a native Windows backend, prefer
  `read_file` through a WSL UNC path over a nested shell command when the
  backend supports that UNC path.
- For a Windows file already mounted at `/mnt/<drive>` in WSL, return to its
  direct `C:/...` form for Windows tools. Do not round-trip through a WSL UNC
  path such as `\\wsl.localhost\<distro>\mnt\c\...`.

### 5. Interpret results correctly

Keep these outcomes separate:

- success with matches;
- success with zero matches;
- invalid pattern or command failure;
- missing/inaccessible root.

Before reporting absence, validate the root and repeat the lookup through an
independent route. For a filename search, cross-check a `search_files` zero
with an explicit file-list operation in the correct domain.

### 6. Report the evidence

State the consumer, environment, root, path spelling, and whether the result
was a match, a clean zero, or a failure. De-duplicate a Windows file seen both
as `C:/...` and `/mnt/c/...`.

## Pitfalls

1. **Shell equals consumer.** Git Bash can launch a native Windows executable;
   the executable still expects a Windows path.
2. **Global MSYS override.** A global `MSYS_NO_PATHCONV` or
   `MSYS2_ARG_CONV_EXCL` breaks unrelated commands. Scope it to one call.
3. **Unnecessary `bash -lc`.** It adds a quoting layer. Use it only for login
   environment requirements.
4. **Hard-coded distribution.** Discover distributions; do not assume a name.
5. **Silent zero.** A zero after timeout, truncation, or root failure is not a
   negative finding.
6. **Slash roulette.** Repeating the same request with different slashes does
   not repair a wrapper that passes the wrong domain to an executable.
7. **Wide scan.** Do not search an entire drive, `/`, or every WSL distribution
   unless the user explicitly requests that scope.
8. **Duplicate counting.** `C:/x` and `/mnt/c/x` may identify the same file.
9. **UNC round-trip.** WSL UNC is for WSL-owned files. Re-exporting `/mnt/c`
   through UNC adds a layer and may be denied even when `C:/...` works.
10. **Terminal interpolation.** Apostrophes, newlines, `$()`, `!`, spaces, and
    Unicode can change meaning across parsers. Use structured tool arguments
    for untrusted patterns instead of constructing a shell command.
11. **GUI equals backend.** A native desktop can manage a WSL backend. Route
    for the process receiving the path, not the visible application.
12. **First distribution wins.** Multiple WSL distributions may expose the
    same mounted Windows file but have different Linux files and runtimes.
    Require project evidence or an explicit choice before selecting one.
13. **Line ending looks like a path failure.** A visible `^M` or a bad
    interpreter error can come from CRLF in a POSIX script. Diagnose encoding
    separately; do not rewrite line endings without authorization.
14. **Nested expansion survives intact.** PowerShell and Git Bash can consume
    `$`, `$()`, `!`, or backslashes before WSL sees them. Prefer direct
    executable arguments and verify the received value instead of trusting a
    successful exit code.
15. **Structured means option-safe.** Some Hermes builds quote search values
    but omit the search program's `-e`/`--` separators. A leading-dash pattern
    can therefore become an option. Use the noncapturing-group route above and
    independently verify the result.

## Verification

- The consuming executable and its domain were identified.
- The Hermes file-tool backend was identified separately from the GUI and
  model server.
- The root was validated in that domain.
- Any MSYS conversion exclusion was local to one command.
- Windows and WSL results are reported separately.
- Every negative claim is backed by a clean search and an independent check.
- Any route that must carry dynamic text was checked with spaces and relevant
  metacharacters, or was kept in a structured tool call.
- No file was moved, deleted, or rewritten during diagnosis.
