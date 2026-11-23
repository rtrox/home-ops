#!/usr/bin/env bash
# Shared helpers for the terraform-plan, terraform-apply and terraform-drift
# workflows. Source this file (`source .github/scripts/tf-ci.sh`); it only
# defines functions and has no side effects.
#
# home-ops is public, so nothing here may print a value read from Doppler,
# state or a live API: jq errors are discarded (they can quote the input),
# every secret is masked as soon as it is assigned, and every failure is a
# generic message.

tf_fail() { echo "::error::could not read the CI credentials from Doppler"; exit 1; }

# tf_get EXPR: print a jq field of the JSON on stdin, or fail without output.
tf_get() { jq -er "$1" 2>/dev/null; }

# tf_set_secret_env masks the value in every later log line and exports it to
# later steps; tf_set_env is for non-secrets (masking "ci" or "1" would blank
# them all over the log).
tf_set_secret_env() {
  echo "::add-mask::$2"
  printf '%s=%s\n' "$1" "$2" >> "$GITHUB_ENV"
}
tf_set_env() { printf '%s=%s\n' "$1" "$2" >> "$GITHUB_ENV"; }

# tf_doppler_secrets TOKEN: print the JSON of the config TOKEN is scoped to.
tf_doppler_secrets() {
  curl -fsS --max-time 30 -K - \
    "https://api.doppler.com/v3/configs/config/secrets/download?format=json" \
    <<<"header = \"Authorization: Bearer ${1}\"" 2>/dev/null
}

# tf_read_credentials TF_TOKEN R2_KEY DOPPLER_CONFIG [HOSTS_TOKEN | -KEY]
#
# Reads the tf-at-home config that TF_TOKEN is scoped to and exports the
# backend and provider credentials to later steps (GITHUB_ENV):
#   R2_KEY                  JSON secret {access_key_id, secret_access_key,
#                           endpoint}: R2_STATE_READONLY (ci) or
#                           R2_STATE_READWRITE (ci-apply)
#   TOFU_STATE_PASSPHRASE   the state/plan encryption passphrase
# The generated providers read tf-at-home through DOPPLER_TOKEN and
# hosts-at-home through var.doppler_hosts_token, both from the config named by
# var.doppler_config (DOPPLER_CONFIG). The fourth argument is that hosts token
# itself, or, when it starts with "-", the name of an OPTIONAL key in the
# tf-at-home config that holds it (ci-apply keeps it there, since an
# Environment has only the one secret).
tf_read_credentials() {
  local tf_token=$1 r2_key=$2 config=$3 hosts=${4:-}
  local secrets r2 passphrase access_key secret_key endpoint
  echo "::add-mask::$tf_token"
  if [ -n "$hosts" ] && [ "${hosts#-}" = "$hosts" ]; then
    echo "::add-mask::$hosts"
  fi

  secrets=$(tf_doppler_secrets "$tf_token") || tf_fail
  r2=$(tf_get ".$r2_key" <<<"$secrets") || tf_fail
  passphrase=$(tf_get '.TOFU_STATE_PASSPHRASE' <<<"$secrets") || tf_fail
  echo "::add-mask::$passphrase"
  access_key=$(tf_get '.access_key_id' <<<"$r2") || tf_fail
  echo "::add-mask::$access_key"
  secret_key=$(tf_get '.secret_access_key' <<<"$r2") || tf_fail
  echo "::add-mask::$secret_key"
  endpoint=$(tf_get '.endpoint' <<<"$r2") || tf_fail
  if [ -n "$hosts" ] && [ "${hosts#-}" != "$hosts" ]; then
    hosts=$(tf_get ".${hosts#-}" <<<"$secrets" || true)
    if [ -n "$hosts" ]; then echo "::add-mask::$hosts"; fi
  fi
  unset secrets r2

  tf_set_secret_env AWS_ACCESS_KEY_ID "$access_key"
  tf_set_secret_env AWS_SECRET_ACCESS_KEY "$secret_key"
  tf_set_secret_env AWS_ENDPOINT_URL_S3 "$endpoint"
  tf_set_secret_env TF_VAR_state_passphrase "$passphrase"
  tf_set_secret_env DOPPLER_TOKEN "$tf_token"
  if [ -n "$hosts" ]; then tf_set_secret_env TF_VAR_doppler_hosts_token "$hosts"; fi
  tf_set_env TF_VAR_doppler_config "$config"
  # Terramate's update check phones home; not from this runner.
  tf_set_env TM_DISABLE_CHECKPOINT 1
}

# tf_excludes: fill the EXCLUDES array from ci-plan-exclude.txt in the current
# directory (one resource address per line, # comments). Their dependents are
# skipped too, so the plan is partial.
tf_excludes() {
  EXCLUDES=()
  [ -f ci-plan-exclude.txt ] || return 0
  local addr
  while IFS= read -r addr; do
    addr=${addr%%#*}
    addr=$(sed -E 's/^[[:space:]]+|[[:space:]]+$//g' <<<"$addr")
    if [ -n "$addr" ]; then EXCLUDES+=("-exclude=$addr"); fi
  done < ci-plan-exclude.txt
  return 0
}

# tf_summary_headers LOG: only the "# <type.name> will be <action>" headers.
# for_each keys and indexes become [...] first, so no key value reaches a
# public place; everything else in the plan is dropped.
tf_summary_headers() {
  sed -E 's/\[[^]]*\]/[…]/g' "$1" \
    | grep -oE '^  # [^ ]+ (will be|must be) (created|updated in-place|destroyed|replaced|read during apply)' || true
}

# tf_summary_totals LOG: the Plan:/No changes line.
tf_summary_totals() {
  grep -oE '^(Plan: [0-9]+ to add, [0-9]+ to change, [0-9]+ to destroy\.|No changes\.)' "$1" || true
}

# tf_summary_hash LOG: a hash of the summary lines. The apply workflow compares
# the hash of the plan that was shown with the one it is about to apply.
tf_summary_hash() {
  { tf_summary_headers "$1"; tf_summary_totals "$1"; } | sha256sum | cut -d' ' -f1
}

# tf_summary_block STACK LOG: the markdown for one stack (EXCLUDES must be set
# by tf_excludes for the same stack).
tf_summary_block() {
  local headers totals
  headers=$(tf_summary_headers "$2")
  totals=$(tf_summary_totals "$2")
  printf '\n#### `%s`\n\n' "$1"
  if [ -n "$headers" ]; then
    printf '```\n%s\n```\n\n' "$headers"
  fi
  printf '%s\n' "${totals:-Plan finished, no summary line found.}"
  if [ ${#EXCLUDES[@]} -gt 0 ]; then
    printf '\n> [!WARNING]\n> **PARTIAL PLAN: %d address(es) excluded.** Check any change to ci-plan-exclude.txt in this PR.\n' "${#EXCLUDES[@]}"
    printf '\nNot planned in CI (ci-plan-exclude.txt, and anything depending on them): %s. Plan these from the laptop.\n' \
      "$(printf '`%s` ' "${EXCLUDES[@]#-exclude=}")"
  fi
}
