#!/usr/bin/env bash
set -euo pipefail

case "${MSYSTEM:-}" in
  MINGW*|MSYS*) ;;
  *) printf 'FAIL: expected Git Bash/MSYS, got MSYSTEM=%s\n' "${MSYSTEM:-}" >&2; exit 1 ;;
esac

exact_exec() (
  POSIXLY_CORRECT=1
  case ":$SHELLOPTS:" in *:posix:*) ;; *) \exit 125;; esac
  \unset -f command builtin exec 2>/dev/null || \exit 124
  \exec "$@"
)

exact_wsl() (
  POSIXLY_CORRECT=1
  case ":$SHELLOPTS:" in *:posix:*) ;; *) \exit 125;; esac
  \unset -f command builtin exec 2>/dev/null || \exit 124
  WSLENV= MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'
  \export WSLENV MSYS_NO_PATHCONV MSYS2_ARG_CONV_EXCL || \exit 123
  \exec "$@"
)

cygpath_bin=/usr/bin/cygpath.exe
[[ -f "$cygpath_bin" && -x "$cygpath_bin" && ! -L "$cygpath_bin" ]] || {
  printf 'FAIL: fixed Git Bash cygpath.exe was not found\n' >&2
  exit 1
}
system_dir=$(exact_exec "$cygpath_bin" -S)
case "$system_dir" in /*) ;; *) printf 'FAIL: Windows system directory was not canonical\n' >&2; exit 1;; esac

hostile_result=$(
  function command { printf 'SPOOF-command\n'; }
  function builtin { printf 'SPOOF-builtin\n'; }
  function exec { printf 'SPOOF-exec\n'; }
  function /usr/bin/cygpath.exe { printf 'SPOOF-path\n'; }
  exact_exec "$cygpath_bin" -S
)
[[ "$hostile_result" == "$system_dir" ]] || {
  printf 'FAIL: a Git Bash function shadow intercepted the exact executable\n' >&2
  exit 1
}

set +e
(
  function command { printf 'SPOOF-readonly\n'; }
  readonly -f command
  exact_exec "$cygpath_bin" -S
) >/dev/null 2>&1
readonly_shadow_status=$?
set -e
[[ $readonly_shadow_status -eq 124 ]] || {
  printf 'FAIL: an unremovable shell shadow did not fail closed\n' >&2
  exit 1
}
powershell_bin="$system_dir/WindowsPowerShell/v1.0/powershell.exe"
wsl_bin="$system_dir/wsl.exe"
[[ -f "$powershell_bin" && -x "$powershell_bin" && ! -L "$powershell_bin" ]] || {
  printf 'FAIL: system Windows PowerShell was not found\n' >&2
  exit 1
}

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
receiver=$(exact_exec "$cygpath_bin" -w "$script_dir/argv-receiver.ps1")
probe='/mnt/c/hermes-skill-probe'

raw=$(exact_exec "$powershell_bin" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$receiver" "$probe")
raw=${raw%$'\r'}
if [[ "$raw" == "$probe" ]]; then
  printf 'FAIL: expected unprotected MSYS path conversion\n' >&2
  exit 1
fi

protected=$(MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' exact_exec "$powershell_bin" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$receiver" "$probe")
protected=${protected%$'\r'}
[[ "$protected" == "$probe" ]] || { printf 'FAIL: per-call conversion exclusion failed\n' >&2; exit 1; }

[[ -z "${MSYS_NO_PATHCONV:-}" ]] || { printf 'FAIL: MSYS_NO_PATHCONV leaked\n' >&2; exit 1; }
[[ -z "${MSYS2_ARG_CONV_EXCL:-}" ]] || { printf 'FAIL: MSYS2_ARG_CONV_EXCL leaked\n' >&2; exit 1; }

special='/mnt/c/space ü/literal-$()-!'
special+="'quote.txt"
received=$(MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' exact_exec "$powershell_bin" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$receiver" "$special")
received=${received%$'\r'}
[[ "$received" == "$special" ]] || { printf 'FAIL: special-character argument changed\n' >&2; exit 1; }

tmp_root=$(mktemp -d)
trap 'rm -rf -- "$tmp_root"' EXIT
printf '%s\n' '- Use exact consumer routing' > "$tmp_root/probe.txt"
mkdir -- "$tmp_root/-fixtures"
printf '%s\n' 'root marker' > "$tmp_root/-fixtures/root.txt"
windows_tmp=$(exact_exec "$cygpath_bin" -m "$tmp_root")

set +e
rg --line-number --no-heading --with-filename '- Use' "$windows_tmp" >/dev/null 2>&1
raw_pattern_exit=$?
set -e
[[ $raw_pattern_exit -ne 0 ]] || { printf 'FAIL: leading-dash pattern was unexpectedly option-safe\n' >&2; exit 1; }
rg --line-number --no-heading --with-filename '(?:- Use)' "$windows_tmp" >/dev/null

(
  cd -- "$tmp_root"
  rg --line-number --no-heading --with-filename 'root marker' './-fixtures' >/dev/null
)

if [[ -n "${HERMES_TEST_WSL_DISTRO:-}" ]]; then
  [[ -f "$wsl_bin" && -x "$wsl_bin" && ! -L "$wsl_bin" ]] || {
    printf 'FAIL: fixed Windows wsl.exe was not found\n' >&2
    exit 1
  }
  distro=$HERMES_TEST_WSL_DISTRO
  required_series=${HERMES_TEST_WSL_PYTHON_SERIES:-}
  case "$required_series" in
    ''|*[!0-9.]*|.*|*.|*.*.*) printf 'FAIL: invalid WSL Python series\n' >&2; exit 1 ;;
    *.*) ;;
    *) printf 'FAIL: invalid WSL Python series\n' >&2; exit 1 ;;
  esac
  runtime_name="python$required_series"
  resolved=()
  [[ ! "0:4755" =~ ^0:([0-7]{3})$ ]] || {
    printf 'FAIL: setuid WSL mode was accepted by the ownership contract\n' >&2
    exit 1
  }
  set +e
  forwarded=$(LD_PRELOAD=/definitely/not/present/release-gate.so WSLENV=LD_PRELOAD exact_wsl "$wsl_bin" -d "$distro" --exec /usr/bin/printenv LD_PRELOAD 2>&1)
  forwarded_status=$?
  set -e
  [[ $forwarded_status -eq 1 && -z "$forwarded" ]] || {
    printf 'FAIL: WSLENV allowed a Windows-side loader variable through\n' >&2
    exit 1
  }
  for candidate in "/usr/bin/$runtime_name" "/usr/local/bin/$runtime_name"; do
    if exact_wsl "$wsl_bin" -d "$distro" --exec /usr/bin/test -e "$candidate"; then
      python_path=$(exact_wsl "$wsl_bin" -d "$distro" --exec /usr/bin/readlink -f -- "$candidate") || exit 1
      python_path=${python_path%$'\r'}
      case "$python_path" in /*) ;; *) printf 'FAIL: WSL runtime path was not absolute\n' >&2; exit 1;; esac
      exact_wsl "$wsl_bin" -d "$distro" --exec /usr/bin/test -f "$python_path" || exit 1
      metadata=$(exact_wsl "$wsl_bin" -d "$distro" --exec /usr/bin/stat -c '%u:%a' -- "$python_path") || exit 1
      metadata=${metadata%$'\r'}
      [[ "$metadata" =~ ^0:([0-7]{3})$ ]] || { printf 'FAIL: WSL runtime ownership/mode mismatch\n' >&2; exit 1; }
      mode=${BASH_REMATCH[1]}
      [[ ${mode: -2:1} != [2367] && ${mode: -1} != [2367] ]] || { printf 'FAIL: WSL runtime is group/other writable\n' >&2; exit 1; }
      exact_wsl "$wsl_bin" -d "$distro" --exec /usr/bin/test -x "$python_path" || exit 1
      [[ " ${resolved[*]} " == *" $python_path "* ]] || resolved+=("$python_path")
    else
      status=$?
      [[ $status -eq 1 ]] || { printf 'FAIL: WSL runtime existence check errored\n' >&2; exit 1; }
    fi
  done
  [[ ${#resolved[@]} -eq 1 ]] || { printf 'FAIL: WSL runtime was absent or ambiguous\n' >&2; exit 1; }
  python_path=${resolved[0]}
  exact_wsl "$wsl_bin" -d "$distro" --exec /usr/bin/test '!' -e "${python_path}._pth" || {
    printf 'FAIL: WSL runtime has an adjacent ._pth override\n' >&2
    exit 1
  }
  identity=$(exact_wsl "$wsl_bin" -d "$distro" --exec /usr/bin/env PYTHONEXECUTABLE=/tmp/foreign-python __PYVENV_LAUNCHER__=/tmp/foreign-venv /usr/bin/env -u PYTHONEXECUTABLE -u __PYVENV_LAUNCHER__ "$python_path" -I -S -B -c 'import sys; print(sys.executable); print("%d.%d.%d" % sys.version_info[:3])')
  identity=${identity//$'\r'/}
  [[ "$identity" == *$'\n'* && "${identity#*$'\n'}" != *$'\n'* ]] || { printf 'FAIL: WSL identity output shape mismatch\n' >&2; exit 1; }
  reported_path=${identity%%$'\n'*}
  reported_version=${identity#*$'\n'}
  [[ "$reported_path" == "$python_path" ]] || { printf 'FAIL: WSL runtime executable mismatch\n' >&2; exit 1; }
  version_prefix=${required_series//./\\.}
  [[ "$reported_version" =~ ^${version_prefix}\.[0-9]+$ ]] || { printf 'FAIL: WSL runtime version mismatch\n' >&2; exit 1; }
fi

printf 'PASS: Git Bash conversion and literal-argument contracts validated.\n'
