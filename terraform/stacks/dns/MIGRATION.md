# Moving DNS into home-ops (migration phase 2, P2-2)

A one-time runbook for the owner. It moves the Cloudflare zones, their WAF
rulesets and their zone-level records out of terraform-record's `cloudflare`
stack into this stack. Delete this file, `imports.tf` and `import-ids.jq` in
the cleanup PR (step 7).

## What moves, and how

Everything is **imported**: the provider reads all of it back in full, and
none of it holds a secret.

| Object | Count | terraform-record address | Here |
| --- | --- | --- | --- |
| Zones | 10 | `module.cf_domain_<zone>.cloudflare_zone.zone` | `module.zone["<zone>"].cloudflare_zone.this` (`prevent_destroy`) |
| Custom WAF rulesets | 10 | `module.cf_domain_<zone>.cloudflare_ruleset.waf_custom_rules` | `module.zone["<zone>"].cloudflare_ruleset.waf_custom_rules` |
| Zone-level records (mail, verification) | 46 | `module.cf_domain_<zone>.cloudflare_dns_record.dns_records[...]` | `cloudflare_dns_record.this["<zone>/<key>"]` |

The zones: `lyb.app`, `missprissquilts.com`, `rtrox.co`, `rtrox.com`,
`rtrox.dev`, `rtrox.io`, `troxel.io`, `trxl.ink`, `trxl.io`, `trxl.tech`.
The records: rtrox.com 3, rtrox.dev 8, rtrox.io 13, troxel.io 13, trxl.io 9.
`import-ids.jq` holds the old key to new key map.

Not moving:

- **rtrox.io's 11 host and cluster A records** (`mini` x3, `nas`, `pve`,
  `backup`, `ns1`, `ns2`, `avahi`, `unifi`, `ztnet`). They belong to the
  stacks for those hosts, which don't exist yet, so they stay in
  terraform-record: forgotten with `module.cf_domain_rtrox_io` and imported
  again there as `cloudflare_dns_record.rtrox_io_host[...]`, the zone found by
  a `cloudflare_zone` data source. The API tokens scoped to rtrox.io find it the
  same way.
- **The registrar's nameservers** (`namedotcom_domain_nameservers` for
  rtrox.dev, trxl.io, trxl.tech). terraform-record forgets them and nothing
  manages them: the domains are moving to Cloudflare Registrar by hand, after
  which Cloudflare keeps the delegation itself. The live delegation is
  untouched. A credential-free check that each zone's public NS delegation
  matches Cloudflare's nameservers is a planned follow-up (not here).
- Everything else in terraform-record `cloudflare` (the API tokens, the
  tunnel, `r2_state_copy`).

Expected plans, in short:

| Stack | Plan |
| --- | --- |
| terraform-record `cloudflare` | `11 to import, 0 to add, 0 to change, 0 to destroy, 80 to forget` |
| `dns` | `66 to import, 0 to add, 0 to change, 0 to destroy` |

The 80 forgets: 10 zones, 10 rulesets, 57 records (the 46 moving here and the
11 host records' old addresses) and the 3 nameserver resources.

## 0. Preconditions

- **Terraform Cloud version.** `import` blocks with `for_each` need Terraform
  1.7 or later; the `arpa-home-cloudflare` workspace already runs `removed`
  blocks, which need the same. Recheck it if in doubt (foundation's
  MIGRATION.md step 0 has the command).
- **Zone count.** The migration plan says 11 zones; terraform-record's code has
  10 (three zones were removed in 2025). If the account has a zone outside
  Terraform, it stays outside, but check it's not one that was meant to be
  managed. Names only; the token goes to curl on stdin, never in its
  arguments:

  ```sh
  T=$(doppler secrets get -p tf-at-home -c prd --plain CLOUDFLARE_TERRAFORM_TOKEN)
  curl -fsS -K - "https://api.cloudflare.com/client/v4/zones?per_page=50" \
    <<<"header = \"Authorization: Bearer ${T}\"" \
    | jq -r '.result[].name' | sort
  unset T
  ```

- **Baseline: both sides plan clean before anything moves.** On
  terraform-record `main`: `env -u TF_VAR_doppler_token tofu -chdir=cloudflare
  plan` says `No changes.` (Remote TFC runs never get your Doppler CLI token;
  the workspace's variable set provides the read-only one.)
- **Freeze.** From here to step 6, no applies to terraform-record `cloudflare`
  and no runs of this stack except the ones below. external-dns keeps
  managing its own records in rtrox.io throughout; neither stack touches them.

## 1. Gather the IDs (laptop, read-only)

Both PRs ship with `"PENDING"` placeholder IDs, which fail the import, so
nothing can be planned until the real ones are in. They come from
terraform-record's state. `tofu state pull` only reads it; the state goes
straight into `jq`, which prints Cloudflare object IDs keyed by address and
nothing else (no record content, no token values). Nothing is written to
disk.

```sh
cd ~/terraform-record
git fetch && git switch p2/dns-removed
# home-ops: replaces the locals block at the bottom of imports.tf.
tofu -chdir=cloudflare state pull | jq -r -f ~/home-ops/terraform/stacks/dns/import-ids.jq
# terraform-record: replaces the IDs locals block in cloudflare/zone_rtrox_io.tf.
tofu -chdir=cloudflare state pull | jq -r -f cloudflare/import-ids.jq
```

The first prints a `zones=10 rulesets=10 records=46` comment line, the second
an 11-entry map. Either fails with a count (never a value) if an object is
missing or doubled; stop and check the state's addresses if so. Paste both
blocks into their files on the PR branches (or hand them to the lead to
commit), then `tofu fmt`.

## 2. Plan both stacks (nothing changes yet)

Plan the new stack before the old one forgets anything, so a mismatch is
found while nothing has moved. Importing in a plan changes nothing.

**terraform-record**, on the PR branch:

```sh
cd ~/terraform-record
env -u TF_VAR_doppler_token tofu -chdir=cloudflare plan -no-color 2>&1 \
  | grep -E '^  # |^Plan:|^No changes|^(Error|Warning):' \
  | sed -E 's/\[[^]]*\]//g; s/module\.cf_domain_[a-z_]+\./module.cf_domain_<zone>./; s/namedotcom_domain_nameservers\.[a-z_]+/namedotcom_domain_nameservers.<name>/' \
  | sort | uniq -c
```

Expect these counts (in some order):

```text
  57   # module.cf_domain_<zone>.cloudflare_dns_record.dns_records will no longer be managed by Terraform
  10   # module.cf_domain_<zone>.cloudflare_ruleset.waf_custom_rules will no longer be managed by Terraform
  10   # module.cf_domain_<zone>.cloudflare_zone.zone will no longer be managed by Terraform
   3   # namedotcom_domain_nameservers.<name> will no longer be managed by Terraform
  11   # cloudflare_dns_record.rtrox_io_host will be imported
Plan: 11 to import, 0 to add, 0 to change, 0 to destroy, 80 to forget.
```

If the workspace's version words the summary differently, the counts and
`0 to destroy` are what matter. A `Warning: Some objects will no longer be
managed by Terraform` is expected. Nothing else may appear: in particular no
`module.cf_api_token_*` update (the token's zone scope now comes from the data
source and must be the same ID) and no `doppler_secret`.

**This stack**, on the home-ops PR branch:

```sh
cd ~/home-ops
task tf:init STACK=dns
task tf:plan STACK=dns -- -no-color 2>&1 | grep -E '^  # |^Plan:|^No changes|^(Error|Warning):'
```

Expect 66 `will be imported` headers (10 `cloudflare_zone.this`, 10
`cloudflare_ruleset.waf_custom_rules`, 46 `cloudflare_dns_record.this`), each
with no attribute change, and:

- No zone may show a change to `account` (its `id`): the account ID comes from
  the rtrox.io lookup (`data.cloudflare_zone.rtrox_io.account.id`), which must
  be the same account terraform-record set on every zone.

```text
Plan: 66 to import, 0 to add, 0 to change, 0 to destroy.
```

**Check what the zones put in state.** `cloudflare_zone` 5.29 (the resource and
the `rtrox_io` data source) has computed, non-sensitive `owner.name` and
`tenant.name` attributes. After the apply they sit in this stack's state, which
CI can decrypt, so check that neither holds a personal name or email. This
saves the plan to a private temp directory, prints counts only (no names), and
deletes the plan:

```sh
cd ~/home-ops
d=$(mktemp -d) && chmod 700 "$d"
task tf:plan STACK=dns -- -out="$d/dns.tfplan" >/dev/null
(
  set -euo pipefail
  r2=$(doppler secrets get -p tf-at-home -c prd --plain R2_STATE_READWRITE)
  AWS_ACCESS_KEY_ID=$(jq -er .access_key_id <<<"$r2")
  AWS_SECRET_ACCESS_KEY=$(jq -er .secret_access_key <<<"$r2")
  AWS_ENDPOINT_URL_S3=$(jq -er .endpoint <<<"$r2")
  TF_VAR_state_passphrase=$(doppler secrets get -p tf-at-home -c prd --plain TOFU_STATE_PASSPHRASE)
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_ENDPOINT_URL_S3 TF_VAR_state_passphrase
  unset r2
  mise exec -- tofu -chdir=terraform/stacks/dns show -json "$d/dns.tfplan" 2>/dev/null \
    | jq -r --arg acct rtrox '
        ( [.resource_changes[] | select(.mode == "managed" and .type == "cloudflare_zone") | .change.after]
          + [.prior_state.values.root_module.resources[]? | select(.mode == "data" and .type == "cloudflare_zone") | .values]
        ) as $z
        | def n(f): [$z[] | select(f)] | length;
          "zones=\($z | length)",
          "owner_name_null=\(n(.owner.name == null)) owner_name_is_account=\(n(.owner.name == $acct)) owner_name_has_at=\(n((.owner.name // "") | contains("@")))",
          "tenant_name_null=\(n(.tenant.name == null)) tenant_name_is_account=\(n(.tenant.name == $acct)) tenant_name_has_at=\(n((.tenant.name // "") | contains("@")))"'
)
rm -rf "$d"
```

Expect `zones=11` (the 10 zones and the data source), `*_has_at=0`, and for
each of owner and tenant, `_null` plus `_is_account` adding up to 11. Anything else (an `@`, or a name that
is neither null nor the account's): **stop before applying** and decide with
the lead whether that value may live in this state. Don't print it to find
out what it is.

### If a plan shows anything else

Don't apply. A plan with imports changes nothing, so the fix is in code: make
the code match the live value (the plan shows it), never accept the change.

| You see | Meaning | Do |
| --- | --- | --- |
| a record **updated in place** (`comment`, `content`, `ttl`, `proxied`, `priority`) | the code here differs from the live record | Match `records.tf` to the plan's current value; re-plan |
| a record update showing only `settings`, `tags` or `private_routing`, here or on a terraform-record `cloudflare_dns_record.rtrox_io_host` import | cloudflare v5 reads an attribute back on import that terraform-record's refreshed state never showed. terraform-record's TFC runs resolve their own `~> 5` provider version, so its 11 host imports can read back differently from this stack's | Set that attribute to the plan's current value, in `records.tf` here or in `cloudflare/zone_rtrox_io.tf` there (e.g. `settings = { flatten_cname = false, ... }`); re-plan |
| a ruleset **updated** (`rules`) | a rule differs: order, `enabled`, `logging`, `action_parameters`, or the API's `ref`/`id` | Match the rule in `zones.tf`; if only computed rule fields (`ref`, `id`, `logging`) differ, set them to the live values |
| a zone **updated** (`type`, `paused`, `vanity_name_servers`) | the zone differs from the code | Match the module to the live value; re-plan |
| any **create** or **must be replaced** | a key here has no import, or an import ID points at the wrong object | Check `imports.tf` against step 1's output; `prevent_destroy` blocks a zone replace anyway |
| `Cannot import non-existent remote object` / `PENDING` | step 1's IDs are missing or wrong | Redo step 1 |
| `module.cf_api_token_*` updates in terraform-record | the rtrox.io data source returned a different zone | Stop: check `zone_rtrox_io.tf`'s data source |
| **anything destroyed**, in either stack | not intended | Stop |

## 3. terraform-record: forget (procedure step 2)

Merge the terraform-record PR once step 2 matches, then from `main`:

```sh
cd ~/terraform-record
git switch main && git pull
env -u TF_VAR_doppler_token tofu -chdir=cloudflare apply    # the same plan; yes
env -u TF_VAR_doppler_token tofu -chdir=cloudflare plan     # No changes.
```

Nothing in Cloudflare or name.com changes; only TFC's state does. Until step 4
nothing manages the zones, rulesets and zone-level records.

## 4. Apply this stack

**Before merging the home-ops PR**, two checks:

- **Nothing applies on merge.** Any merge under `terraform/` triggers
  `terraform-apply`, which applies every `ci-apply` stack. This must print
  nothing; if it lists a stack, ask the owner before merging:

  ```sh
  cd ~/home-ops/terraform && mise exec -- terramate list --tags ci-apply
  ```

- **CI can read this stack.** From the merge on, the nightly `terraform-drift`
  run (03:30 Pacific) plans this stack with CI's read-only token. home-ops
  #2211 gives that token `Zone WAF Read` (the rulesets), the only permission
  it lacks: the account ID comes from a zone lookup, which `Zone Read` covers.
  Apply #2211 (foundation, laptop) before this PR merges, or the drift run
  fails on this stack.

Then merge, and from `main`:

```sh
cd ~/home-ops
git switch main && git pull
task tf:plan STACK=dns      # 66 to import, 0 to add, 0 to change, 0 to destroy
task tf:apply STACK=dns     # review, then yes
```

## 5. Zero-diff gate

Both must say `No changes.`:

```sh
task tf:plan STACK=dns
env -u TF_VAR_doppler_token tofu -chdir="$HOME/terraform-record/cloudflare" plan
```

Then check that the consumers of the zone are unaffected: external-dns in
mini still syncs (`kubectl -n network logs deploy/external-dns --since=1h`
shows no Cloudflare errors), and the proxmox stack still plans clean (its ACME token
finds rtrox.io by name). The freeze ends here.

## 6. Follow-ups

1. **CI** (decided by the owner; foundation's change, not this stack's):
   - `tf-at-home/ci`'s read-only token (foundation `ci_readonly.tf`) has
     `Zone Read` and `DNS Read` on every zone in the account. Plans of this
     stack also need **`Zone WAF Read`** (the custom rulesets), added by
     #2211. No account permission: the account ID comes from the rtrox.io zone
     lookup, and `Account Settings Read` (which listing accounts needs) also
     reads account members and audit logs.
   - `tf-at-home/ci-apply` needs a Cloudflare token that can write what this
     stack manages: `Zone Write` (account-scoped, for zone edits and new
     zones), `DNS Write` and `Zone WAF Write` on every zone in the account,
     created by foundation under the key name `CLOUDFLARE_TERRAFORM_TOKEN`.
     That key name is shared by every `ci-apply` stack using the cloudflare
     provider, so it would carry the union of their permissions.
2. **Tag the stack** `["ci-apply", "gated"]` in a separate PR, once step 5
   passed and the CI credentials above exist. That PR's merge plans (and, after
   approval in `tofu-apply-gated`, applies) this stack in CI: it must plan `No
   changes.`
3. **Cleanup PRs.** Here: delete `imports.tf`, `import-ids.jq` and this file.
   terraform-record: delete the import block, its IDs and `import-ids.jq` from
   `cloudflare/zone_rtrox_io.tf`, `dns_moved.tf`'s removed blocks,
   `modules/cf_domain/`, and the namedotcom provider (block, `required_providers`
   entry, lock file entry). Each must plan `No changes.`

## Rollback

- **Before step 3:** nothing has changed. Close or fix the PRs.
- **After step 3, before step 4 succeeds:** the objects are live and
  untouched, just unmanaged. **Never revert the terraform-record PR first.**
  After its apply, a plain revert plans two things:
  - **It destroys the 11 live rtrox.io host A records**
    (`cloudflare_dns_record.rtrox_io_host[...]`: the mini API x3, nas, backup,
    pve, ns1, ns2, avahi, unifi, ztnet), because the revert drops that
    resource while its state holds them. That takes the Kubernetes API name,
    the NAS and the DNS servers' names off the internet.
  - It creates everything that moved again, because the old addresses are no
    longer in state: duplicate records, and zone creates that fail.

  Either finish step 4, or first roll the `arpa-home-cloudflare` workspace
  back to its state version from before step 3 (TFC keeps every version; the
  freeze means nothing else was written since). Only then revert the PR, and
  plan: it must say `No changes.` before anything is applied.
- **Step 4 fails partway:** imports are state-only. Fix the cause and re-run
  `task tf:apply STACK=dns`; already-imported objects drop out of the plan.
- **After step 4, if this stack must give them back:** `removed { destroy =
  false }` blocks here, and import blocks at the old addresses in
  terraform-record with the same IDs. Never let either stack plan a destroy of
  a zone.
