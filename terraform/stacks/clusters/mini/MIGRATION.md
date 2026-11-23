# Moving mini's Terraform into home-ops (migration phase 2, P2-3)

A one-time runbook for the owner. It moves what mini needs from outside the
cluster out of terraform-record's `cloudflare` and `backblaze` stacks into
this stack. The backups of the root of trust and mini's controller tokens go
to `foundation` instead (see its MIGRATION.md, "P2-3"). The cleanup PR (step
11) deletes this file, `imports.tf` and `p2-3-plan.json`.

The PRs, in merge order:

| PR | What | Merged at |
| --- | --- | --- |
| home-ops #2226 | `ci-skip` tag in the three Terraform workflows | step 0 |
| home-ops #2227 | volsync's B2 restic password from its own Doppler key (a Flux apply) | step 1 |
| home-ops #2223 | foundation: backups, controller tokens, `CLOUDFLARE_MINI_TOKEN`, `task tf:check-plan` | step 2 |
| home-ops #2224 | this stack (stacked on #2223; retarget to `main` once #2223 merges) | step 6 |
| rtrox/terraform-record#66 | forget what moves, except the old credentials and the old tunnel | step 4 |
| rtrox/terraform-record#67 | delete the old credentials and the old tunnel (rebase onto `main` after #66 merges) | step 10 |

The stack is tagged `ci-skip` (CI doesn't touch it) and is applied from the
laptop. `ci-apply` comes in a later PR ([CI](#ci)).

## What moves, and how

| Object | To | Method |
| --- | --- | --- |
| `mini.rtrox.io` A ×3 (`rtrox_io_host["mini_0".."mini_2"]`) | `cloudflare_dns_record.api[<node>]`, addresses from `inventory/hosts.yaml` | import by ID |
| Tunnel `mini_external_ingress` and its `random_id` | none: a **new** tunnel `mini-external-ingress` with a new `random_bytes` secret | new; terraform-record deletes the old one in #67 |
| `CLOUDFLARED_CREDENTIALS` (same JSON keys) | `doppler_secret.cloudflared_credentials` | import, updated to the new tunnel |
| Bucket `k8s-rtrox-io-volsync-store` (4 lifecycle rules) | `module.volsync_store` | import, unchanged |
| Its key `k8s-mini-rtrox-io-volsync-store` | new key, same name and capabilities | rotate |
| `random_password.volsync_restic_password` | none: copied once into the hand-made `VOLSYNC_B2_RESTIC_PASSWORD` | forgotten, never destroyed |
| `VOLSYNC_BACKBLAZE_BUCKET` | `doppler_secret.volsync_bucket`, without `restic_password` | import, updated to the new key |
| Bucket `k8s-mini-rtrox-io-cnpg-offsite` (Object Lock governance 45 days) | `module.cnpg_offsite_store` | import, unchanged |
| Its keys: the writer and `-restore` (read-only, for DR) | new keys, same names and capabilities | rotate |
| `CNPG_OFFSITE_BACKBLAZE_BUCKET`, `CNPG_OFFSITE_RESTORE_BACKBLAZE_BUCKET` | `doppler_secret.cnpg_offsite_bucket`, `.cnpg_offsite_restore_bucket` | import, updated to the new keys |
| external-dns and cert-manager tokens, their Doppler secrets | foundation (`mini_cluster_tokens.tf`) | rotate / import |
| `tofu-state-copy` token, `rtrox-tofu-state-history` and `k8s-mini-rtrox-io-secrets-backup` buckets and keys, their three secrets | foundation (`backups.tf`) | rotate / import |

Not moving: MinIO (phase 4 replaces it with Garage), and the TrueNAS bucket
and tokens. Nothing is imported by value.

## Conventions

- **Every plan is separate from its apply, with a stop in between.** Plan to
  a file, check it, read it, and only then apply that same file. Applying a
  saved plan doesn't ask again.
- **Machine check.** `task tf:check-plan STACK=<stack> PLAN=<file>
  EXPECT=<json>` pipes `tofu show -json` of the plan straight into
  `terraform/scripts/plan-check.jq`. It prints addresses and kinds only. It
  fails on anything not listed in the stack's `p2-3-plan*.json`: an unexpected
  change or import, a missing one, any destroy, or a new Doppler value that
  isn't built from what the apply creates. For this stack it also requires
  `CLOUDFLARED_CREDENTIALS` to be built from the new tunnel and secret.
- **Secrets never on screen.** Values only ever move through pipes. Checks
  compare SHA-256 hashes and print `yes`/`NO`. There are no here-strings: zsh
  writes those to temp files. `TF_LOG` is unset for every run, because a trace
  log would hold the secrets:

  ```sh
  tf() { env -u TF_LOG -u TF_LOG_PATH task "$@"; }
  h() { sha256sum | cut -c1-64; }                                     # hash of stdin
  dop() { doppler secrets get "$1" -p k8s-at-home -c min --plain | jq -Rsj 'rtrimstr("\n")'; }
  dopf() { doppler secrets get "$1" -p k8s-at-home -c min --plain | jq -j --arg f "$2" '.[$f]'; }
  bak() { age -d -i "$AGE_KEY" "$BACKUP_DIR/mini-min-$STAMP.json.age" | jq -j --arg k "$1" --arg f "${2:-}" 'if $f == "" then .[$k] else (.[$k] | fromjson | .[$f]) end'; }
  k8s() { kubectl get secret -n "$1" "$2" -o json | jq -j --arg f "$3" '.data[$f] | @base64d'; }
  same() { if [ "$2" = "$3" ]; then echo "$1: yes"; else echo "$1: NO"; fi; }
  differ() { if [ "$2" != "$3" ]; then echo "$1: yes"; else echo "$1: NO"; fi; }
  # Every app's B2 volsync Secret, as "namespace secret" (from the ExternalSecrets, which hold no values).
  vs_list() { kubectl get externalsecret -A -o json | jq -r '.items[] | select(.metadata.name | endswith("-volsync-b2")) | "\(.metadata.namespace) \(.metadata.name)-secret"'; }
  ```

  Every `NO` below means stop, unless the step says otherwise.
- Times are Pacific. The CronJobs run in UTC: volsync B2 movers at 4:00 pm,
  cnpg-offsite at 6:00 pm, tofu-state-copy at 8:00 pm, and doppler-export on
  Saturdays at 7:00 pm.

## 0. Preconditions

- **TFC workspaces.** Both must run Terraform 1.7 or later (removed blocks;
  #66 also raises `backblaze`'s `required_version` to `>= 1.7.0`), in
  **remote** execution mode, and must **not** auto-apply from VCS. Otherwise
  merging #66 or #67 would apply before you've seen its plan:

  ```sh
  TFC=$(jq -r '.credentials["app.terraform.io"].token' ~/.terraform.d/credentials.tfrc.json)
  for w in arpa-home-cloudflare arpa-home-backblaze; do
    printf 'header = "Authorization: Bearer %s"\n' "$TFC" \
      | curl -fsS -K - "https://app.terraform.io/api/v2/organizations/rtrox/workspaces/$w" \
      | jq -r --arg w "$w" '.data.attributes | "\($w) version=\(."terraform-version") mode=\(."execution-mode") auto-apply=\(."auto-apply") vcs=\(."vcs-repo" != null)"'
  done
  unset TFC
  ```

  Expect `version` of 1.7 or later, `mode=remote`, and `auto-apply=false` or
  `vcs=false`. Note which workspaces say `vcs=true`: TFC refuses CLI applies
  on them, so steps 4b and 10b confirm their VCS runs in the UI instead.
- **Baseline: everything plans clean.** On terraform-record `main`, both
  `env -u TF_VAR_doppler_token tofu -chdir=cloudflare plan` and the same for
  `backblaze`. Here, `tf tf:plan STACK=foundation`. Each must say
  `No changes.` Anything else: resolve it first.
- **#2226 merged** (the `ci-skip` tag), so CI never plans this stack.
- **Freeze**, from here to step 10:
  - no applies to terraform-record `cloudflare` or `backblaze`, `foundation`
    or this stack except the ones below;
  - no changes to cloudflared, external-dns, cert-manager, the volsync
    component, cnpg-offsite, doppler-export or tofu-state-copy;
  - no Renovate merges in either repo that touch `terraform/**`, those apps or
    terraform-record. Pause Renovate's automerge for the window.
- **Don't use `task volsync:restic-env`**: it prints the restic password and
  keys. `task volsync:snapshots` doesn't.
- **Back up the secrets that change**, age-encrypted, never printed. This is
  the rollback until step 10:

  ```sh
  BACKUP_DIR="$HOME/tofu-backups"; mkdir -p "$BACKUP_DIR" && chmod 700 "$BACKUP_DIR"
  AGE_KEY="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
  STAMP=$(date +%Y%m%dT%H%M%S)
  doppler secrets download -p k8s-at-home -c min --no-file --format json \
    | jq '{EXTERNALDNS_CLOUDFLARE_TOKEN, CERTMANAGER_CLOUDFLARE_TOKEN, CLOUDFLARED_CREDENTIALS,
           VOLSYNC_BACKBLAZE_BUCKET, CNPG_OFFSITE_BACKBLAZE_BUCKET, CNPG_OFFSITE_RESTORE_BACKBLAZE_BUCKET,
           TOFU_STATE_R2_SOURCE, TOFU_STATE_HISTORY_BACKBLAZE_BUCKET, SECRETS_BACKUP_BACKBLAZE_BUCKET}' \
    | age --encrypt -i "$AGE_KEY" -o "$BACKUP_DIR/mini-min-$STAMP.json.age"
  age -d -i "$AGE_KEY" "$BACKUP_DIR/mini-min-$STAMP.json.age" | jq -r 'to_entries[] | "\(.key) set=\(.value != null)"'
  ```

  Expect nine names, all `set=true`. Keep `BACKUP_DIR`, `AGE_KEY` and `STAMP`
  for the whole run.

## 1. The restic password leaves Terraform

The password every B2 repository is encrypted with must never change, and no
mover may ever see it missing. So the cluster switches to a hand-made key
**before** Terraform stops writing the old field (step 6).

Run step 1 well away from the B2 movers' run (4:00 pm), so no mover starts
while the Secrets re-render.

**1a. Copy it into its own key** (no echo), then check it matches. The first
command only checks the field is there and has the right shape (it prints
nothing), so the copy never writes an empty value:

```sh
( set -euo pipefail
  doppler secrets get VOLSYNC_BACKBLAZE_BUCKET -p k8s-at-home -c min --plain \
    | jq -e '.restic_password | type == "string" and test("^[A-Za-z0-9]{32}$")' >/dev/null
  doppler secrets get VOLSYNC_BACKBLAZE_BUCKET -p k8s-at-home -c min --plain \
    | jq -je '.restic_password // error("restic_password missing")' \
    | doppler secrets set VOLSYNC_B2_RESTIC_PASSWORD -p k8s-at-home -c min --silent >/dev/null ) \
  && echo "copied" || echo "copy FAILED"
same "new key is 32 characters" "$(dop VOLSYNC_B2_RESTIC_PASSWORD | wc -c | tr -d ' ')" 32
same "new key = old field" "$(dop VOLSYNC_B2_RESTIC_PASSWORD | h)" "$(dopf VOLSYNC_BACKBLAZE_BUCKET restic_password | h)"
```

(`doppler secrets set NAME` reads a piped value from stdin. Check
`doppler secrets set --help` on your CLI version first.) Leave the key
`masked`. doppler-export backs it up weekly with the rest of `min`.

**1b. Record every B2 Secret's password, by hash:**

```sh
vs_list | while read -r ns s; do printf '%s/%s %s\n' "$ns" "$s" "$(k8s "$ns" "$s" RESTIC_PASSWORD | h)"; done \
  > "$BACKUP_DIR/restic-before-$STAMP.txt"
same "22 B2 Secrets" "$(wc -l < "$BACKUP_DIR/restic-before-$STAMP.txt" | tr -d ' ')" 22
same "one password" "$(cut -d' ' -f2 "$BACKUP_DIR/restic-before-$STAMP.txt" | sort -u | wc -l | tr -d ' ')" 1
same "Secrets use the Doppler password" "$(cut -d' ' -f2 "$BACKUP_DIR/restic-before-$STAMP.txt" | sort -u)" "$(dop VOLSYNC_B2_RESTIC_PASSWORD | h)"
```

Expect `yes` ×3. There are 22 because paperless includes the volsync
component twice. If the count differs, find out why before going on (a new
app is fine: update the number here).

**1c. Merge #2227** (a Flux apply). Once Flux has reconciled the apps,
force-sync the ExternalSecrets:

```sh
vs_list | while read -r ns s; do kubectl annotate externalsecret -n "$ns" "${s%-secret}" force-sync="$(date +%s)" --overwrite >/dev/null; done
```

**1d. Check.** Every Secret's password must be unchanged, and every
ExternalSecret Ready:

```sh
vs_list | while read -r ns s; do
  same "$ns/$s RESTIC_PASSWORD unchanged" "$(k8s "$ns" "$s" RESTIC_PASSWORD | h)" "$(grep -F "$ns/$s " "$BACKUP_DIR/restic-before-$STAMP.txt" | cut -d' ' -f2)"
done
kubectl get externalsecret -A | grep -- '-volsync-b2 ' | grep -vc 'SecretSynced'   # 0
# #2227 is live in every one, including any whose Flux Kustomization is suspended:
kubectl get externalsecret -A -o json | jq '[.items[] | select(.metadata.name | endswith("-volsync-b2"))
  | select([.spec.data[]?.remoteRef.key] | index("VOLSYNC_B2_RESTIC_PASSWORD") | not)] | length'   # 0
```

**Stop** on any `NO` or a non-zero count. A non-zero second count means some
app hasn't picked up #2227 (a suspended or failing Kustomization). Step 6
would then leave that app's template without a password (an empty one or a
failed sync), so fix it first. To back out, revert #2227. That is safe only
until step 6: the old field is still in Doppler until then.

## 2. Foundation: the mini token alone

Merge #2223. Then plan only the token, check it, stop, and apply:

```sh
git switch main && git pull
P="$BACKUP_DIR/foundation-token-$STAMP.tfplan"
tf tf:plan STACK=foundation -- -no-color -out="$P" -target=doppler_secret.mini_token_prd 2>&1 | grep -E '^  # |^Plan:|^No changes|^(Error|Warning):'
tf tf:check-plan STACK=foundation PLAN="$P" EXPECT=p2-3-plan-token.json
```

Expect `Plan: 3 to add, 0 to change, 0 to destroy.` (`time_rotating.mini_token`,
`cloudflare_api_token.mini`, `doppler_secret.mini_token_prd`), a targeting
warning, and `PASS: 3 changes`. **Stop and read it.** Then:

```sh
tf tf:apply STACK=foundation -- "$P" && rm -f "$P"
```

**Never apply foundation untargeted before step 5.** Its imports would adopt
objects terraform-record still manages.

## 3. Plan both new stacks, before anything is forgotten

Plans change nothing, so check them now, while terraform-record still manages
everything.

```sh
P="$BACKUP_DIR/foundation-$STAMP.tfplan"
tf tf:plan STACK=foundation -- -no-color -out="$P" 2>&1 | grep -E '^Plan:|^No changes|^(Error|Warning):'
tf tf:check-plan STACK=foundation PLAN="$P" EXPECT=p2-3-plan.json; rm -f "$P"
```

Expect `Plan: 7 to import, 5 to add, 5 to change, 0 to destroy.` and `PASS`.
Foundation's MIGRATION.md lists them.

This stack, from #2224's branch:

```sh
git switch <#2224's branch> && git pull
tf tf:init STACK=clusters/mini
P="$BACKUP_DIR/clusters-mini-$STAMP.tfplan"
tf tf:plan STACK=clusters/mini -- -no-color -out="$P" 2>&1 | grep -E '^  # |^Plan:|^No changes|^(Error|Warning):'
tf tf:check-plan STACK=clusters/mini PLAN="$P" EXPECT=p2-3-plan.json; rm -f "$P"
```

Expect `Plan: 9 to import, 5 to add, 4 to change, 0 to destroy.` and `PASS:
14 changes`:

- **9 imports**, each `will be imported` and nothing else:
  `cloudflare_dns_record.api` ×3 (`node01`..`node03`),
  `module.volsync_store.b2_bucket.this`, `module.cnpg_offsite_store.b2_bucket.this`;
  and four `doppler_secret`s, which are also updated (below).
- **5 creates**: `random_bytes.tunnel_secret`,
  `cloudflare_zero_trust_tunnel_cloudflared.mini`, and three
  `b2_application_key.this`: volsync, cnpg-offsite, cnpg-offsite-restore.
- **4 updates**, `value` only: `doppler_secret.cloudflared_credentials` (to
  the new tunnel), `.volsync_bucket` (new key, no `restic_password`),
  `.cnpg_offsite_bucket`, `.cnpg_offsite_restore_bucket`.

### If a plan or check shows anything else

Don't apply. Fix the code and plan again.

| You see | Meaning | Do |
| --- | --- | --- |
| a bucket updated, only reordering `lifecycle_rules` | B2 returned the rules in another order | Reorder them in the code to match the plan's current order |
| a bucket updated otherwise, or **must be replaced** (`prevent_destroy` error) | the code differs from the bucket | Match the code to the plan's current values. A bucket's settings don't change in this move |
| a record updated | content, comment, proxied or TTL differ | Match `api_records.tf` or `inventory/hosts.yaml` to the live record |
| a `doppler_secret` update showing `visibility` or `value_type` | the secret isn't `masked`/`string` | Set that attribute to the live value; only `value` may change |
| `A tunnel with this name already exists` | the name is taken | Pick another `name` in `tunnel.tf` |
| a 403 on the tunnel | `CLOUDFLARE_MINI_TOKEN` can't read tunnels | Add `Cloudflare Tunnel Read` in foundation's `mini_token.tf` and redo step 2 |
| `FAIL:` from the check | the plan differs from `p2-3-plan.json` | Read the line; never edit the JSON to make a surprise pass |
| **anything destroyed** | not intended | Stop |

## 4. Forget, in terraform-record (TFC)

**4a. Plan #66** on its branch, in each workspace. Remote TFC runs must never
get your Doppler CLI token, so unset it:

```sh
cd ~/terraform-record && git switch p2/mini-removed && git pull
for s in cloudflare backblaze; do
  env -u TF_VAR_doppler_token -u TF_LOG -u TF_LOG_PATH tofu -chdir=$s plan -no-color 2>&1 \
    | grep -E '^  # |^Plan:|^No changes|^(Error|Warning):'
done
```

`cloudflare`: 3 records moved to
`cloudflare_dns_record.rtrox_io_host_moved_to_clusters_mini[...]`, then 7
forgotten: those 3 records,
`doppler_secret.argo_tunnel_mini_secret`, `.cf_api_token_mini_external_dns`,
`.cf_api_token_mini_certmanager` and `.r2_state_copy_mini`.
`Plan: 0 to add, 0 to change, 0 to destroy, 7 to forget.`
The tunnel, its `random_id` and the old tokens must **not** appear.

`backblaze`: 5 keys moved out of their modules to `b2_application_key.old_*`,
then 10 forgotten: the four `module.bb_bucket_*.b2_bucket.bucket`,
`random_password.volsync_restic_password` and five `doppler_secret`s.
`Plan: 0 to add, 0 to change, 0 to destroy, 10 to forget.`
If a moved key shows any update or replacement, its arguments differ from the
module's. A replaced key would cut its consumer off.

The `Warning: Some objects will no longer be managed` is expected. If the
workspace's Terraform words the summary differently, what matters is the
headers and `0 to destroy`. **Stop and read both.**

**4b. Apply.** Merge #66, then from `main` apply each workspace, type `yes`
only for the same plan, and plan again:

```sh
git switch main && git pull
env -u TF_VAR_doppler_token -u TF_LOG -u TF_LOG_PATH tofu -chdir=cloudflare apply
env -u TF_VAR_doppler_token -u TF_LOG -u TF_LOG_PATH tofu -chdir=backblaze apply
for s in cloudflare backblaze; do env -u TF_VAR_doppler_token tofu -chdir=$s plan -no-color | grep -E '^Plan:|^No changes'; done
```

If step 0 showed a workspace with `vcs=true`, TFC refuses the CLI `apply`
there. Merging queues a VCS run instead: open it in the TFC UI, check its
resource headers and `Plan:` line match the plan you read in 4a exactly, and
only then confirm it. Discard it if anything differs.

Nothing in Cloudflare, B2 or Doppler changes, only TFC's state. Then rebase
#67 onto `main`.

## 5. Apply foundation

```sh
cd ~/home-ops && git switch main && git pull
P="$BACKUP_DIR/foundation-$STAMP.tfplan"
tf tf:plan STACK=foundation -- -no-color -out="$P" 2>&1 | grep -E '^Plan:|^No changes|^(Error|Warning):'
tf tf:check-plan STACK=foundation PLAN="$P" EXPECT=p2-3-plan.json
```

Expect the same as step 3. **Stop and read it**, then
`tf tf:apply STACK=foundation -- "$P" && rm -f "$P"`.

## 6. Apply this stack

Only with step 1d all `yes`. Merge #2224 (retargeted to `main`), then:

```sh
git switch main && git pull
P="$BACKUP_DIR/clusters-mini-$STAMP.tfplan"
tf tf:plan STACK=clusters/mini -- -no-color -out="$P" 2>&1 | grep -E '^Plan:|^No changes|^(Error|Warning):'
tf tf:check-plan STACK=clusters/mini PLAN="$P" EXPECT=p2-3-plan.json
```

Expect the same as step 3. **Stop and read it.** Applying it starts the tunnel
cutover (step 7), so be ready to run that straight after:

```sh
tf tf:apply STACK=clusters/mini -- "$P" && rm -f "$P"
```

Doppler now holds the new tunnel, keys and tokens. The old keys, tokens and
tunnel stay valid until step 10, so a consumer on the old value keeps working,
except cloudflared, which follows `CLOUDFLARED_CREDENTIALS` (step 7).

## 7. Tunnel cutover

Expect a **public ingress blip of a few minutes**: from cloudflared
restarting on the new tunnel until `min-ext.rtrox.io`'s CNAME points at it.
Internal routes aren't affected.

**7a. external-dns on its new token first**, so that the CNAME change below
is made with it. Reloader restarts external-dns when its Secret changes:

```sh
kubectl annotate externalsecret -n network externaldns-cloudflare-token force-sync="$(date +%s)" --overwrite
until same x "$(k8s network externaldns-cloudflare-token cloudflare-token | h)" "$(dop EXTERNALDNS_CLOUDFLARE_TOKEN | h)" | grep -q yes; do sleep 5; done
kubectl -n network rollout status deploy/external-dns --timeout=5m
```

**7b. The cutover**, without pauses. Force-sync cloudflared's two
ExternalSecrets, wait until the substitution Secret has the new endpoint,
reconcile the Kustomizations at once (which sets the DNSEndpoint's target),
then wait for cloudflared's rollout (Reloader restarts it on the new
TUNNEL_TOKEN):

```sh
NEW=$(dopf CLOUDFLARED_CREDENTIALS TunnelID); OLD=$(bak CLOUDFLARED_CREDENTIALS TunnelID); ACCT=$(dopf CLOUDFLARED_CREDENTIALS AccountTag)
echo "new=$NEW old=$OLD"
kubectl annotate externalsecret -n network cloudflared cloudflared-substitution-secret force-sync="$(date +%s)" --overwrite
until [ "$(k8s network cloudflared-substitution-secret TUNNEL_ENDPOINT)" = "$NEW.cfargotunnel.com" ]; do sleep 5; done
flux reconcile kustomization cloudflared-config -n network && flux reconcile kustomization cloudflared -n network
kubectl -n network rollout status deploy/cloudflared --timeout=5m
```

external-dns then updates the record on its next sync, within a minute or two.

**7c. Check**, printing only tunnel IDs and statuses (not secrets):

```sh
same "cloudflared's token is the new tunnel" "$(k8s network cloudflared-secret TUNNEL_TOKEN | base64 -d | jq -j .t)" "$NEW"
same "DNSEndpoint targets it" "$(kubectl -n network get dnsendpoint cloudflared-tunnel -o jsonpath='{.spec.endpoints[0].targets[0]}')" "$NEW.cfargotunnel.com"
cf() { doppler secrets get CLOUDFLARE_MINI_TOKEN -p tf-at-home -c prd --plain | jq -Rsj 'rtrimstr("\n") | "header = \"Authorization: Bearer \(.)\"\n"' | curl -fsS -K - "https://api.cloudflare.com/client/v4/$1"; }
ZONE=$(cf "zones?name=rtrox.io" | jq -r '.result[0].id')
same "min-ext.rtrox.io CNAME target" "$(cf "zones/$ZONE/dns_records?name=min-ext.rtrox.io&type=CNAME" | jq -r '.result[0].content')" "$NEW.cfargotunnel.com"
for t in "$NEW" "$OLD"; do cf "accounts/$ACCT/cfd_tunnel/$t" | jq -r '.result | "\(.name) status=\(.status) connections=\(.connections | length)"'; done
```

Expect `yes` ×3, the new tunnel `healthy` with connections, and the old one
`inactive` or `down` with none. Then a public route answers. List them with
`kubectl get httproute -A -o json | jq -r '.items[] | select(any(.spec.parentRefs[]; .name == "envoy-external")) | .spec.hostnames[]'`
and run `curl -sS -o /dev/null -w '%{http_code}\n' https://<one of them>/`,
which expects that app's usual status, not a 52x.

If public ingress is still down after 10 minutes: [rollback](#if-something-goes-wrong).

## 8. Check every consumer has the NEW credential

Each consumer's Secret must equal Doppler now, and Doppler must differ from
the backup. Together that proves the new credential reached it. Force-sync to
check at once instead of waiting up to an hour:

```sh
kubectl annotate externalsecret -n network externaldns-cloudflare-token force-sync="$(date +%s)" --overwrite
kubectl annotate externalsecret -n cert-manager cloudflare-token-secret force-sync="$(date +%s)" --overwrite
kubectl annotate externalsecret -n database cnpg-offsite force-sync="$(date +%s)" --overwrite
kubectl annotate externalsecret -n terraform tofu-state-copy force-sync="$(date +%s)" --overwrite
kubectl annotate externalsecret -n security doppler-export force-sync="$(date +%s)" --overwrite
vs_list | while read -r ns s; do kubectl annotate externalsecret -n "$ns" "${s%-secret}" force-sync="$(date +%s)" --overwrite >/dev/null; done
```

```sh
# new LABEL NS SECRET FIELD KEY [JSONFIELD]: the cluster Secret = Doppler, and Doppler != the backup.
new() {
  local d; if [ -n "${6:-}" ]; then d=$(dopf "$5" "$6" | h); else d=$(dop "$5" | h); fi
  same "$1 = Doppler" "$(k8s "$2" "$3" "$4" | h)" "$d"
  differ "$1 is new" "$d" "$(bak "$5" ${6:+"$6"} | h)"
}
new external-dns network externaldns-cloudflare-token cloudflare-token EXTERNALDNS_CLOUDFLARE_TOKEN
new cert-manager cert-manager cloudflare-token-secret cloudflare-token CERTMANAGER_CLOUDFLARE_TOKEN
vs_list | while read -r ns s; do
  new "$ns/$s key id" "$ns" "$s" AWS_ACCESS_KEY_ID VOLSYNC_BACKBLAZE_BUCKET application_key_id
  new "$ns/$s key" "$ns" "$s" AWS_SECRET_ACCESS_KEY VOLSYNC_BACKBLAZE_BUCKET application_key
  same "$ns/$s RESTIC_PASSWORD unchanged" "$(k8s "$ns" "$s" RESTIC_PASSWORD | h)" "$(grep -F "$ns/$s " "$BACKUP_DIR/restic-before-$STAMP.txt" | cut -d' ' -f2)"
done
new "cnpg-offsite key id" database cnpg-offsite-secret RCLONE_CONFIG_OFFSITE_ACCOUNT CNPG_OFFSITE_BACKBLAZE_BUCKET application_key_id
new "cnpg-offsite key" database cnpg-offsite-secret RCLONE_CONFIG_OFFSITE_KEY CNPG_OFFSITE_BACKBLAZE_BUCKET application_key
new "tofu-state-copy R2 id" terraform tofu-state-copy-secret RCLONE_CONFIG_R2_ACCESS_KEY_ID TOFU_STATE_R2_SOURCE access_key_id
new "tofu-state-copy R2 key" terraform tofu-state-copy-secret RCLONE_CONFIG_R2_SECRET_ACCESS_KEY TOFU_STATE_R2_SOURCE secret_access_key
new "tofu-state-copy B2 id" terraform tofu-state-copy-secret RCLONE_CONFIG_HISTORY_ACCOUNT TOFU_STATE_HISTORY_BACKBLAZE_BUCKET application_key_id
new "tofu-state-copy B2 key" terraform tofu-state-copy-secret RCLONE_CONFIG_HISTORY_KEY TOFU_STATE_HISTORY_BACKBLAZE_BUCKET application_key
new "doppler-export B2 id" security doppler-export-secret RCLONE_CONFIG_B2_ACCOUNT SECRETS_BACKUP_BACKBLAZE_BUCKET application_key_id
new "doppler-export B2 key" security doppler-export-secret RCLONE_CONFIG_B2_KEY SECRETS_BACKUP_BACKBLAZE_BUCKET application_key
```

Every line `yes`. Then each consumer works on it:

1. **external-dns** restarted (Reloader), and
   `kubectl -n network logs deploy/external-dns --since=15m | grep -ciE '403|unauthorized|authentication'`
   prints `0`. Step 7's CNAME update, made after 7a, proved it can write with
   the new token.
2. **cert-manager**, **required before step 10**: one DNS-01 challenge must
   clear on the new token. Pick a certificate (`kubectl get certificates -A`),
   renew it, and watch:

   ```sh
   kubectl get certificate -n <ns> <cert> -o jsonpath='{.status.notAfter}{"\n"}'   # note it
   cmctl renew -n <ns> <cert>
   kubectl get challenges -A -w            # one appears, goes valid, and is removed
   kubectl get certificaterequest -n <ns>  # the newest one: APPROVED True, READY True
   kubectl get certificate -n <ns> <cert> -o jsonpath='{.status.notAfter}{"\n"}'   # later than before
   ```

   Then `kubectl get certificates -A` is all `READY True` and
   `kubectl get challenges -A` is empty. A challenge stuck `pending` with a
   Cloudflare error means the new token doesn't work: [rollback](#if-something-goes-wrong).
3. **volsync**: `task volsync:snapshots APP=<app> NAMESPACE=<ns> BACKEND=b2`
   lists snapshots (the new key and the unchanged password open the
   repository). After the next run (4:00 pm), every B2 source succeeded:
   `kubectl get replicationsource -A -o json | jq -r '.items[] | select(.metadata.name | endswith("-b2")) | "\(.metadata.namespace)/\(.metadata.name) \(.status.lastSyncTime) \(.status.latestMoverStatus.result)"'`.
4. **cnpg-offsite**, **tofu-state-copy**, **doppler-export**: a run of each
   succeeds and pings healthchecks.io. To run them now:
   `kubectl create job -n database --from=cronjob/cnpg-offsite cnpg-offsite-p2-3`,
   `kubectl create job -n terraform --from=cronjob/tofu-state-copy tofu-state-copy-p2-3`,
   `kubectl create job -n security --from=cronjob/doppler-export doppler-export-p2-3`.
5. **The CNPG restore key** (nothing in the cluster reads it): it can list
   the bucket, with rclone installed and nothing printed:

   ```sh
   ( export RCLONE_CONFIG_R_TYPE=b2
     RCLONE_CONFIG_R_ACCOUNT=$(dopf CNPG_OFFSITE_RESTORE_BACKBLAZE_BUCKET application_key_id); export RCLONE_CONFIG_R_ACCOUNT
     RCLONE_CONFIG_R_KEY=$(dopf CNPG_OFFSITE_RESTORE_BACKBLAZE_BUCKET application_key); export RCLONE_CONFIG_R_KEY
     rclone lsf --max-depth 1 "r:$(dopf CNPG_OFFSITE_RESTORE_BACKBLAZE_BUCKET bucket)" >/dev/null && echo "restore key lists: yes" || echo "restore key lists: NO" )
   ```

## 9. Wait

Leave the old credentials and the old tunnel for one full nightly cycle
(volsync, cnpg-offsite, tofu-state-copy) and one doppler-export run (or the
manual jobs), so a consumer that reads at a different time proves it's
healthy too. Until step 10, everything is reversible from the backup.

## 10. Delete the old credentials and the old tunnel

**10a. Right before**, step 8 must be all `yes`, including 8.2's cleared
DNS-01 challenge, and both new stacks must say `No changes.`:

```sh
cd ~/home-ops && git switch main && git pull
tf tf:plan STACK=foundation -- -no-color 2>&1 | grep -E '^Plan:|^No changes'
tf tf:plan STACK=clusters/mini -- -no-color 2>&1 | grep -E '^Plan:|^No changes'
```

Re-run step 7's tunnel status line: the old tunnel must have no connections
(Cloudflare refuses to delete a connected tunnel).

**10b. Plan #67** (rebased onto `main`) on its branch, each workspace as in
step 4a:

```text
cloudflare:
  # cloudflare_api_token.r2_state_copy will be destroyed
  # cloudflare_zero_trust_tunnel_cloudflared.auto_tunnel_mini will be destroyed
  # module.cf_api_token_mini_certmanager.cloudflare_api_token.token will be destroyed
  # module.cf_api_token_mini_external_dns.cloudflare_api_token.token will be destroyed
  # random_id.argo_secret_mini will be destroyed
Plan: 0 to add, 0 to change, 5 to destroy.
backblaze:
  # b2_application_key.old_mini_cnpg_offsite will be destroyed
  # b2_application_key.old_mini_cnpg_offsite_restore will be destroyed
  # b2_application_key.old_mini_secrets_backup will be destroyed
  # b2_application_key.old_tofu_state_history will be destroyed
  # b2_application_key.old_volsync_store will be destroyed
Plan: 0 to add, 0 to change, 5 to destroy.
```

Anything else: don't apply. **Stop and read both.** Then merge #67 and apply
each workspace from `main` as in step 4b (on a `vcs=true` workspace, confirm
the VCS run in the TFC UI only if its headers match the plan above).
Afterwards, re-run step 8's checks
1, 3 (`snapshots`) and 5, and watch the next nightly runs.

## 11. Zero-diff gate, cleanup, then CI

All four say `No changes.`: `tf tf:plan` for `foundation` and
`clusters/mini`, and both terraform-record workspaces. The freeze ends here.

1. **Cleanup PR**: delete `imports.tf`, `p2-3-plan.json` and this file, and
   foundation's P2-3 imports and `p2-3-plan*.json`. Its plans: `No changes.`
   terraform-record's removed blocks and `doppler.min_write` aliases go in its
   own cleanup.
2. **CI** ([below](#ci)), then the PR that swaps `ci-skip` for `ci-apply`.

Delete the backups (`mini-min-*`, `restic-before-*`) once the gate has held
for a week.

## If something goes wrong

- **Step 1**: before step 6, revert #2227 and force-sync; the old field still
  holds the password. A `NO` in 1d means some Secret's password differs:
  revert, and don't continue until it's understood.
- **Step 2** only created a token nothing reads yet. Nothing to undo.
- **Step 4 (forget) misbehaves**: forgetting edits only TFC's state. Don't
  apply foundation or this stack. Either carry on (steps 5 and 6 adopt
  everything), or revert #66 and adopt the objects back in terraform-record
  with `import` blocks (the same IDs as `imports.tf` here). Either plan must
  be imports only. The restic password can't be re-imported there by value
  any more; it lives in `VOLSYNC_B2_RESTIC_PASSWORD` now.
- **Step 5 or 6 fails partway**: what it did is in state. The old
  credentials still work, so consumers keep working whichever secrets were
  updated. Fix the cause, then plan, check and apply again.
- **Public ingress down after step 7**: go back to the old tunnel, which
  exists until #67. Restore `CLOUDFLARED_CREDENTIALS` from the backup (no
  echo), force-sync, and reconcile as in step 7:

  ```sh
  bak CLOUDFLARED_CREDENTIALS | doppler secrets set CLOUDFLARED_CREDENTIALS -p k8s-at-home -c min --silent >/dev/null
  ```

  cloudflared reconnects to the old tunnel, and the CNAME follows. This
  stack's next plan then shows that secret updating back to the new tunnel.
  Find out why it failed before applying again.
- **Another new credential doesn't work** (a step 8 check fails): restore
  that secret the same way, `bak <KEY> | doppler secrets set <KEY> ...`, and
  force-sync its ExternalSecret. The old credential works until step 10.
  For `VOLSYNC_BACKBLAZE_BUCKET` the restored JSON includes the old
  `restic_password` field again, which nothing reads any more.
- **After step 10** the old credentials and tunnel are gone, so rollback is
  forward: reissue the broken credential (`-replace` it in the stack that owns
  it); its Doppler secret follows.
- **Something destroyed**: nothing here plans a destroy before #67, the
  checker fails on any, and the buckets, the tunnel and its secret have
  `prevent_destroy`. Stop and look. Never edit state by hand.

## CI

`ci-skip` keeps CI off this stack. The PR that swaps it for `ci-apply` needs
CI to plan it with read-only credentials, and to apply it with
`tf-at-home/ci-apply`:

| For CI | Plan (`ci`) | Apply (`ci-apply`) |
| --- | --- | --- |
| Cloudflare | `CLOUDFLARE_MINI_TOKEN` = the read-only CI token, plus an account-level `Cloudflare Tunnel Read` on `ci_readonly` | `CLOUDFLARE_MINI_TOKEN` = the real token (foundation adds the `doppler_secret` then, not before: every ci-apply job downloads the whole config) |
| B2 | `BACKBLAZE_APPLICATION_KEY_ID`/`_KEY`: a hand-made read-only key (`listBuckets`, `readBuckets`, `listKeys`, and whatever reading file-lock settings needs), no file reads | a key that can create keys on these two buckets (`writeKeys` is account-wide in B2, so this is effectively the provider key; decide then) |
| Doppler | a read token on `k8s-at-home/min_tf` (below) | `DOPPLER_MINI_WRITE_TOKEN`, a write token on `min_tf` |

**Doppler: a Terraform-only config.** A read token on `k8s-at-home/min` would
read every secret of every app in mini, and every PR plan job reads `ci`.
Instead, the secrets Terraform writes move to their own config:

1. foundation creates a `k8s-at-home` environment `min_tf`, an import of its
   root config, and its write token (`doppler_write_tokens`).
2. This stack (and foundation's two mini writes) write their keys to `min_tf`
   instead of `min`.
3. In `min`, each of those keys becomes a reference, `${min_tf.KEY}`.
   References are on Doppler's free plan; config inheritance isn't. So
   ExternalSecrets keep reading `min`, unchanged.
4. CI's plan token reads `min_tf`, which holds exactly what this stack's
   state already holds, and no app secret.

The cutover moves each secret: write it to `min_tf`, then set the reference
in `min`, then check the cluster Secret is unchanged (by hash, as in step 8),
then forget and re-import at the new address. Each is a separate,
plan-checked step in that PR.

**State.** This stack's state uses the shared passphrase: `ci-skip`, unlike
`laptop-only`, doesn't change that. So CI could decrypt it once it exists,
even while `ci-skip` keeps CI from planning it. A same-repo PR's job on the
runner has the shared passphrase and the read-only R2 token that reads every
key. After this move the state holds the new tunnel secret and three B2
keys. It doesn't hold the restic password or the controller tokens.

**Before `ci-apply`, narrow the volsync key.** It still has the old default
capabilities, `deleteFiles` included, on a bucket without Object Lock. A
leaked key (from this state, or from the cluster) could therefore delete
every B2 backup. Narrow it to what restic needs before CI holds anything
that can read it. Check whether pruning, which on this bucket hides files,
needs `deleteFiles` at all. If it does, protect the bucket another way, e.g.
a retention setting the key can't override.
