#!/usr/bin/env bash
# Tests for the summary helpers in tf-ci.sh. Run: .github/scripts/test-tf-ci.sh
# The summary and its hash are what an approver sees and what the apply job
# compares, so every kind of plan line must show up in both.
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$here/tf-ci.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0

check() { # NAME CONDITION-RESULT
  if [ "$2" = ok ]; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi
}

log=$tmp/plan.log
cat >"$log" <<'LOG'
OpenTofu will perform the following actions:

  # aws_thing.created will be created
  + resource "aws_thing" "created" {
      # (known after apply)
    }

  # aws_thing.updated will be updated in-place
  # aws_thing.destroyed will be destroyed
  # aws_thing.replaced must be replaced
  # data.x.read will be read during apply
  # aws_thing.imported["secret key"] will be imported
  # aws_thing.gone will be removed from the OpenTofu state
  # aws_thing.old has moved to aws_thing.new["other key"]
  # aws_thing.removed will no longer be managed by OpenTofu, but will not be destroyed

Plan: 1 to import, 2 to add, 1 to change, 1 to destroy, 1 to forget.
LOG

headers=$(tf_summary_headers "$log")
for want in "will be created" "will be updated in-place" "will be destroyed" "must be replaced" \
  "will be read during apply" "will be imported" "will be removed from the OpenTofu state" \
  "has moved to" "will no longer be managed"; do
  if grep -qF "$want" <<<"$headers"; then check "header: $want" ok; else check "header: $want" no; fi
done
if grep -qF 'secret key' <<<"$headers"; then check "keys are redacted" no; else check "keys are redacted" ok; fi
if [ "$(tf_summary_totals "$log")" = "Plan: 1 to import, 2 to add, 1 to change, 1 to destroy, 1 to forget." ]; then
  check "totals with import and forget" ok
else check "totals with import and forget" no; fi

printf 'Plan: 1 to add, 0 to change, 0 to destroy.\n' >"$tmp/a.log"
printf 'No changes. Your infrastructure matches the configuration.\n' >"$tmp/b.log"
printf 'Changes to Outputs:\n  + x = 1\n' >"$tmp/c.log"
if [ "$(tf_summary_totals "$tmp/a.log")" = "Plan: 1 to add, 0 to change, 0 to destroy." ]; then check "totals: plain plan" ok; else check "totals: plain plan" no; fi
if [ "$(tf_summary_totals "$tmp/b.log")" = "No changes." ]; then check "totals: no changes" ok; else check "totals: no changes" no; fi
if [ "$(tf_summary_totals "$tmp/c.log")" = "Changes to Outputs:" ]; then check "totals: outputs only" ok; else check "totals: outputs only" no; fi

# The hash must change when a header or the totals change, and a plan with
# changes must never hash like an empty one.
empty=$(: | sha256sum | cut -d' ' -f1)
h1=$(tf_summary_hash "$log")
sed 's/will be imported/will be created/' "$log" >"$tmp/d.log"
sed 's/1 to forget/0 to forget/' "$log" >"$tmp/e.log"
if [ "$h1" != "$empty" ]; then check "hash of a real plan is not the empty hash" ok; else check "hash of a real plan is not the empty hash" no; fi
if [ "$h1" != "$(tf_summary_hash "$tmp/d.log")" ]; then check "hash covers headers" ok; else check "hash covers headers" no; fi
if [ "$h1" != "$(tf_summary_hash "$tmp/e.log")" ]; then check "hash covers totals" ok; else check "hash covers totals" no; fi

exit "$fails"
