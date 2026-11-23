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

# tf_read_credentials TF_TOKEN R2_KEY [HOSTS_TOKEN | -KEY]
#
# Reads the tf-at-home config that TF_TOKEN is scoped to (ci, or ci-apply) and
# exports the backend credentials to later steps (GITHUB_ENV):
#   R2_KEY                  JSON secret {access_key_id, secret_access_key,
#                           endpoint}: R2_STATE_READONLY (ci) or
#                           R2_STATE_READWRITE (ci-apply)
#   TOFU_STATE_PASSPHRASE   the state/plan encryption passphrase
# Provider credentials are NOT read here: they differ per stack, so each stack
# loop calls tf_export_provider_env. For that, DOPPLER_TOKEN (TF_TOKEN) and
# TF_CI_HOSTS_TOKEN are exported. The third argument is the hosts-at-home
# token itself, or, when it starts with "-", the name of an OPTIONAL key in the
# tf-at-home config that holds it (ci-apply keeps it there, since an
# Environment has only the one secret).
tf_read_credentials() {
  local tf_token=$1 r2_key=$2 hosts=${3:-}
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
  if [ -n "$hosts" ]; then tf_set_secret_env TF_CI_HOSTS_TOKEN "$hosts"; fi
  # Terramate's update check phones home; not from this runner.
  tf_set_env TM_DISABLE_CHECKPOINT 1
}

# tf_export_provider_env: run in a stack's directory. Reads the stack's
# generated _provider_env.json ([{env, project, key}]) and exports each named
# variable into THIS shell (not GITHUB_ENV). Each value comes from the config
# its project's token is scoped to (tf-at-home: DOPPLER_TOKEN, hosts-at-home:
# TF_CI_HOSTS_TOKEN) and is masked first. Variables set for a previous stack
# are unset. Only the listed keys reach the environment; nothing is printed,
# and a failure is a generic message and return 1.
TF_PROVIDER_ENV_NAMES=()
tf_export_provider_env() {
  local n name project key token value rows line
  local -A cache=()
  for n in "${TF_PROVIDER_ENV_NAMES[@]}"; do unset "$n"; done
  TF_PROVIDER_ENV_NAMES=()
  [ -f _provider_env.json ] || { echo "::error::no _provider_env.json (run terramate generate)"; return 1; }
  rows=$(jq -r 'if type == "array" and all(.[]; (.env | type) == "string" and (.project | type) == "string" and (.key | type) == "string")
    then .[] | [.env, .project, .key] | @tsv else error end' _provider_env.json 2>/dev/null) \
    || { echo "::error::malformed _provider_env.json"; return 1; }
  while IFS=$'\t' read -r name project key; do
    [ -n "$name" ] || continue
    case $project in
      tf-at-home) token=${DOPPLER_TOKEN:-} ;;
      hosts-at-home) token=${TF_CI_HOSTS_TOKEN:-} ;;
      *) echo "::error::unknown Doppler project in _provider_env.json"; return 1 ;;
    esac
    [ -n "$token" ] || { echo "::error::no CI token for $project"; return 1; }
    if [ -z "${cache[$project]:-}" ]; then
      cache[$project]=$(tf_doppler_secrets "$token") || { echo "::error::could not read $project"; return 1; }
    fi
    value=$(jq -er --arg k "$key" '.[$k] | strings' <<<"${cache[$project]}" 2>/dev/null) || { echo "::error::could not read a provider credential from $project"; return 1; }
    # Mask every line: a multi-line value is otherwise only masked per line.
    while IFS= read -r line; do
      if [ -n "$line" ]; then echo "::add-mask::$line"; fi
    done <<<"$value"
    export "$name=$value"
    TF_PROVIDER_ENV_NAMES+=("$name")
  done <<<"$rows"
  return 0
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
    | grep -E '^  # [^ ]+ (will|must|has) ' || true
}

# tf_summary_totals LOG: the Plan: line (any mix of import, add, change,
# destroy and forget), "No changes." and an outputs-only change.
tf_summary_totals() {
  grep -oE '^(Plan: .*\.$|No changes\.|Changes to Outputs:)' "$1" || true
}

# tf_list ARRAY ARGS...: fill ARRAY with `terramate list --run-order ARGS`, one
# stack path per element, in run order (terramate's default is path order). A
# failing list is an error, never an empty list. Run from terraform/.
tf_list() {
  local -n _tf_out=$1
  shift
  local raw
  raw=$(terramate list --run-order "$@") || { echo "::error::terramate list failed"; return 1; }
  _tf_out=()
  if [ -n "$raw" ]; then mapfile -t _tf_out <<<"$raw"; fi
  return 0
}

# tf_summary_hash LOG: a hash of the summary lines. The apply workflow compares
# the hash of the plan that was shown with the one it is about to apply.
tf_summary_hash() {
  { tf_summary_headers "$1"; tf_summary_totals "$1"; } | sha256sum | cut -d' ' -f1
}

# tf_plan_gate JSON LOG: decide whether a stack's apply needs approval. JSON is
# `tofu show -json` of the saved plan, LOG the text plan. Prints a short
# reason (counts only, never values) and returns 0 when the apply is GATED, 1
# when it may run straight away. Gated means the plan destroys, replaces
# (create-then-destroy and destroy-then-create both carry "delete") or forgets
# anything. Fail closed: a missing or unparsable JSON, or a text plan whose
# totals show a destroy or forget the JSON missed, is gated.
tf_plan_gate() {
  local json=$1 log=$2 counts del forget totals tdel tforget
  # Allowlist: every change must carry an actions array made only of known
  # actions; anything else (missing change or actions, unknown or
  # differently-cased action) is an error, hence gated.
  counts=$(jq -r 'if (type == "object") and (.format_version | type) == "string"
      and ((.resource_changes // []) | type) == "array"
    then (.resource_changes // []) as $rc
      | if all($rc[]; (.change | type) == "object" and (.change.actions | type) == "array"
          and (.change.actions | length) > 0
          and all(.change.actions[]; IN("no-op", "create", "read", "update", "delete", "forget")))
        then "\([$rc[] | select(.change.actions | index("delete"))] | length) \([$rc[] | select(.change.actions | index("forget"))] | length)"
        else error end
    else error end' "$json" 2>/dev/null) || counts=""
  if ! [[ $counts =~ ^[0-9]+\ [0-9]+$ ]]; then
    echo "could not read the plan to check it for destroys, replaces and forgets"
    return 0
  fi
  read -r del forget <<<"$counts"
  totals=$(tf_summary_totals "$log")
  # Exactly one well-formed Plan: line, or none (no changes, outputs only).
  # More than one, or one we cannot parse, is gated.
  if [ "$(grep -c '^Plan: ' <<<"$totals" || true)" -gt 1 ] \
    || { grep -q '^Plan: ' <<<"$totals" && ! grep -qE '^Plan: [0-9]+ to [a-z]+(, [0-9]+ to [a-z]+)*\.$' <<<"$totals"; }; then
    echo "could not read the plan totals to check them for destroys and forgets"
    return 0
  fi
  tdel=$(grep -oE '[0-9]+ to destroy' <<<"$totals" | grep -oE '^[0-9]+' || true)
  tforget=$(grep -oE '[0-9]+ to forget' <<<"$totals" | grep -oE '^[0-9]+' || true)
  if [ "${tdel:-0}" -gt "$del" ]; then del=$tdel; fi
  if [ "${tforget:-0}" -gt "$forget" ]; then forget=$tforget; fi
  if [ "$del" -gt 0 ] || [ "$forget" -gt 0 ]; then
    echo "plan has $del to destroy or replace and $forget to forget"
    return 0
  fi
  return 1
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
