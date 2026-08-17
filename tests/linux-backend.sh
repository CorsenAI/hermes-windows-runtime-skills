#!/usr/bin/env bash
set -euo pipefail

expect_wsl=0
if [[ "${1:-}" == '--expect-wsl' ]]; then expect_wsl=1; fi

tmp_root=$(mktemp -d)
trap 'rm -rf -- "$tmp_root"' EXIT
mkdir -p -- "$tmp_root/space ü/literal-\$()-!"
test -d "$tmp_root/space ü/literal-\$()-!"

token=${tmp_root#/tmp/}
[[ ! -e "C:/$token" ]] || { printf 'FAIL: Windows path unexpectedly resolved on Linux\n' >&2; exit 1; }
[[ ! -e "/c/$token" ]] || { printf 'FAIL: MSYS path unexpectedly resolved on Linux\n' >&2; exit 1; }

kernel=$(uname -r)
if (( expect_wsl )); then
  [[ "$kernel" == *Microsoft* || "$kernel" == *microsoft* ]] || { printf 'FAIL: expected a WSL kernel\n' >&2; exit 1; }
  [[ -d /mnt/c ]] || { printf 'FAIL: /mnt/c is unavailable in WSL\n' >&2; exit 1; }
else
  [[ "$kernel" != *Microsoft* && "$kernel" != *microsoft* ]] || { printf 'FAIL: plain-Linux test ran inside WSL\n' >&2; exit 1; }
fi

printf 'PASS: Linux backend path contracts validated (WSL=%s).\n' "$expect_wsl"
