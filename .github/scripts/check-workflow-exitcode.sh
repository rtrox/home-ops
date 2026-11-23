#!/usr/bin/env bash
# Guard: GitHub runs `run:` steps as `bash -e`, so a command that can exit
# non-zero on purpose (tofu plan -detailed-exitcode exits 2) must be captured
# on its own line with `|| rc=$?`. A bare `rc=$?` line after it is never
# reached, because bash -e has already ended the step.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
shopt -s nullglob
bad=0
for f in .github/workflows/*.yaml .github/workflows/*.yml; do
  # A bare `rc=$?` line.
  if grep -nE '^\s*rc=\$\?\s*$' "$f"; then
    echo "^^ $f: bare 'rc=\$?' line; under bash -e the step ends before it. Use 'cmd || rc=\$?' with 'rc=0' before it." >&2
    bad=1
  fi
  # -detailed-exitcode without `|| rc=$?` on the same line.
  if grep -n -- '-detailed-exitcode' "$f" | grep -vE '\|\|\s*rc=\$\?'; then
    echo "^^ $f: -detailed-exitcode command not captured with '|| rc=\$?' on the same line." >&2
    bad=1
  fi
done
exit "$bad"
