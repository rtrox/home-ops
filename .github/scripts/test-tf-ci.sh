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

# tf_export_provider_env: only the listed keys, per project token, masked.
tf_doppler_secrets() { # stub: the config each token is scoped to
  case $1 in
    tf-tok) echo '{"A_KEY":"aval","OTHER":"nope"}' ;;
    hosts-tok) echo '{"H_KEY":"hval"}' ;;
    *) return 1 ;;
  esac
}
mkdir "$tmp/stack"
printf '[{"env":"A_ENV","project":"tf-at-home","key":"A_KEY"},{"env":"H_ENV","project":"hosts-at-home","key":"H_KEY"}]\n' >"$tmp/stack/_provider_env.json"
(
  cd "$tmp/stack" || exit 1
  export DOPPLER_TOKEN=tf-tok TF_CI_HOSTS_TOKEN=hosts-tok
  tf_export_provider_env >"$tmp/mask.out"
  [ "$A_ENV" = aval ] && [ "$H_ENV" = hval ] && [ -z "${OTHER:-}" ] || exit 1
  grep -q '::add-mask::aval' "$tmp/mask.out" && grep -q '::add-mask::hval' "$tmp/mask.out" || exit 2
  printf '[]\n' >_provider_env.json
  tf_export_provider_env >/dev/null
  [ -z "${A_ENV:-}" ] || exit 3
  printf '[{"env":"X","project":"tf-at-home","key":"MISSING"}]\n' >_provider_env.json
  ! tf_export_provider_env >/dev/null || exit 4
  # A key with jq metacharacters is looked up literally, not spliced in.
  printf '[{"env":"Q","project":"tf-at-home","key":"A_KEY\\"] | error"}]\n' >_provider_env.json
  ! tf_export_provider_env >/dev/null || exit 5
  # Malformed mapping: fail closed, export nothing.
  printf 'not json' >_provider_env.json
  ! tf_export_provider_env >/dev/null || exit 6
  printf '{"env":"A"}' >_provider_env.json
  ! tf_export_provider_env >/dev/null || exit 7
  # Every line of a multi-line value is masked.
  tf_doppler_secrets() { echo '{"ML":"line1\nline2"}'; }
  printf '[{"env":"M","project":"tf-at-home","key":"ML"}]\n' >_provider_env.json
  tf_export_provider_env >"$tmp/mask2.out" || exit 8
  grep -q '::add-mask::line1' "$tmp/mask2.out" && grep -q '::add-mask::line2' "$tmp/mask2.out" || exit 9
)
rc=$?
if [ $rc -eq 0 ]; then check "provider env: exports, masks, unsets, fails closed" ok; else check "provider env (rc=$rc)" no; fi

exit "$fails"
