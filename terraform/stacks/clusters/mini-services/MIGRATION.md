# Moving pocket-id's Terraform into home-ops (migration phase 2, P2-4)

A one-time runbook for the owner. It moves terraform-record's `pocketid` stack
(TFC workspace `arpa-home-pocketid`, local execution) into this stack. Nothing
in pocket-id or Doppler changes: terraform-record forgets, this stack imports.
No credential is rotated. The cleanup PR (step 5) deletes this file,
`imports.tf` and `p2-4-plan.json`.

| PR | What | Merged at |
| --- | --- | --- |
| home-ops #2236 | this stack | step 4 |
| rtrox/terraform-record#68 | forget everything in `pocketid` | step 3 |

The stack is tagged `ci-skip` (CI doesn't touch it) and is applied from the
laptop. `ci-apply` comes in a later PR ([CI](#ci)).

## What moves, and how

| Object | To | Method |
| --- | --- | --- |
| Groups `family`, `admins` | `pocketid_group.this["family"]`, `["admins"]` | import, ID found by name |
| Clients Actual, autobrr, Booklore, Grafana, Komga, Paperless, qui, Shelfmark, Sure | `pocketid_client.this[<app>]` | import, ID found by name |
| `SURE_POCKETID_CLIENT`, `ACTUAL_POCKETID_CLIENT` (`k8s-at-home/min`) | none | let go: forgotten, never destroyed; phase 3 rotates them |

Every confidential client's secret was set by hand and isn't in either state
(pocket-id never returns it after creation), so no Doppler secret built from
one can be imported: its first apply would overwrite the live value. The other
clients' Doppler secrets (`GRAFANA_POCKETID_CLIENT`, ...) aren't in Terraform,
and nor are pocket-id's users.

## Conventions

As in `clusters/mini`'s MIGRATION.md: plan to a file, check it, read it, and
apply only that file. `task tf:check-plan` fails on anything not in
`p2-4-plan.json`. Nothing here prints a secret. `TF_LOG` stays unset:

```sh
tf() { env -u TF_LOG -u TF_LOG_PATH task "$@"; }
old() { env -u TF_LOG -u TF_LOG_PATH TF_VAR_doppler_token="$(doppler configure get token --plain)" tofu -chdir=pocketid "$@"; }
PLANS="$HOME/tofu-backups"; mkdir -p "$PLANS" && chmod 700 "$PLANS"; STAMP=$(date +%Y%m%dT%H%M%S)
```

`old` is for terraform-record, run from `~/terraform-record`. `arpa-home-pocketid`
runs locally, so the CLI token stays on the laptop.

## 0. Preconditions

- **Local execution.** `arpa-home-pocketid` must still be in **local**
  execution mode, or a remote run would upload `TF_VAR_doppler_token`:

  ```sh
  TFC=$(jq -r '.credentials["app.terraform.io"].token' ~/.terraform.d/credentials.tfrc.json)
  printf 'header = "Authorization: Bearer %s"\n' "$TFC" \
    | curl -fsS -K - https://app.terraform.io/api/v2/organizations/rtrox/workspaces/arpa-home-pocketid \
    | jq -r '.data.attributes."execution-mode"'
  unset TFC
  ```

  Expect `local`. Your `tofu` must be 1.7 or later (removed blocks).
- **Baseline.** On terraform-record `main`, `old plan -no-color | grep -E '^Plan:|^No changes'`
  says `No changes.`
- **The key.** `doppler secrets get POCKETID_API_TOKEN -p tf-at-home -c prd --plain | wc -c`
  is more than 0 (terraform-record reads the same key).
- **Freeze**, to step 4: no group or client edits in pocket-id's admin UI, no
  other `pocketid` applies, and no Renovate automerge (pause it as #2230 did
  for P2-3).

## 1. Plan this stack, before anything is forgotten

From this PR's branch:

```sh
cd ~/home-ops && git switch p2-4/mini-services && git pull
tf tf:init STACK=clusters/mini-services
P="$PLANS/mini-services-$STAMP.tfplan"
out=$(tf tf:plan STACK=clusters/mini-services -- -no-color -out="$P" 2>&1)
printf '%s\n' "$out" | grep -E '^  # |^Plan:|^No changes|^(Error|Warning):'
tf tf:check-plan STACK=clusters/mini-services PLAN="$P" EXPECT=p2-4-plan.json; rm -f "$P"
```

Expect `Plan: 11 to import, 0 to add, 0 to change, 0 to destroy.` and `PASS:
11 changes`: two `pocketid_group.this` and nine `pocketid_client.this`, each
`will be imported` and nothing else.

**Same objects as terraform-record's?** The imports find each ID by name, so
check they're the IDs terraform-record's state holds. IDs aren't secret; this
prints them only if they differ:

```sh
new=$(printf '%s\n' "$out" | awk '/^  # .* will be imported$/ {a = $2} /^  # \(imported from "/ {gsub(/^  # \(imported from "|"\)$/, ""); print a, $0}' | sort)
was=$(cd ~/terraform-record && git switch -q main && git pull -q && old show -json \
  | jq -r '.values.root_module.resources[] | select(.type | startswith("pocketid_")) | "\(.type).this[\"\(.name)\"] \(.values.id)"' | sort)
if [ -n "$new" ] && [ "$new" = "$was" ]; then echo "IDs: same"; else diff <(echo "$was") <(echo "$new"); fi
```

Expect `IDs: same`.

### If the plan or check shows anything else

Don't apply. Fix the code and plan again.

| You see | Meaning | Do |
| --- | --- | --- |
| `Invalid index` in `imports.tf` | no group or client has that name | Match `name` in `pocketid.tf` to pocket-id's |
| `one()` error: more than one element | two objects share the name | Find out why; delete the stray by hand only if it's unused |
| a client or group updated | the code differs from pocket-id | Match `pocketid.tf` to the live value. The move changes nothing |
| a client or group **created** or destroyed | not intended | Stop |
| `FAIL:` from the check | the plan differs from `p2-4-plan.json` | Read the line; never edit the JSON to make a surprise pass |

## 2. Plan the forget, in terraform-record

```sh
cd ~/terraform-record && git switch p2/pocketid-removed && git pull
old init -input=false >/dev/null
old plan -input=false -no-color 2>&1 | grep -E '^  # |^Plan:|^No changes|^(Error|Warning):'
```

Expect 13 resources that `will be removed from the OpenTofu state but will
not be destroyed`: `pocketid_group.family`, `.admins`, the nine
`pocketid_client`s, `doppler_secret.actual_pocketid_client` and
`.sure_pocketid_client`, and
`Plan: 0 to add, 0 to change, 0 to destroy, 13 to forget.` The `Warning: Some
objects will no longer be managed` is expected. Anything to add, change or
destroy: stop.

## 3. Forget

Merge rtrox/terraform-record#68, then from `main`:

```sh
git switch main && git pull
old apply      # type yes only for the same 13 forgets
old plan -no-color | grep -E '^Plan:|^No changes'
```

Expect `No changes.` Only TFC's state changed. Until step 4 nothing manages
these objects, which is harmless: nothing changes them either.

## 4. Apply this stack

Merging #2236 runs `terraform-apply` for every `ci-apply` stack; each
should plan `No changes`, and this stack, `ci-skip`, isn't touched. Then:

```sh
cd ~/home-ops && git switch main && git pull
P="$PLANS/mini-services-$STAMP.tfplan"
tf tf:plan STACK=clusters/mini-services -- -no-color -out="$P" 2>&1 | grep -E '^Plan:|^No changes|^(Error|Warning):'
tf tf:check-plan STACK=clusters/mini-services PLAN="$P" EXPECT=p2-4-plan.json
```

Expect the same as step 1. **Stop and read it**, then
`tf tf:apply STACK=clusters/mini-services -- "$P" && rm -f "$P"`.

## 5. Zero-diff gate, then cleanup

Both say `No changes.`: `tf tf:plan STACK=clusters/mini-services` and
`old plan`. Log in to one app (Grafana) to be sure. The freeze ends here.

1. **Cleanup PR, here**: delete `imports.tf`, `p2-4-plan.json` and this file.
   Its plan: `No changes.` (the lookups leave the state).
2. **terraform-record**: delete `pocketid/` and its README line. Then delete
   the `arpa-home-pocketid` workspace once `old state list` shows only
   `data.doppler_secrets.tf_read`. That data source keeps a copy of all of
   `tf-at-home/prd` in the workspace's state, so deleting the workspace
   removes it and its old versions.

## If something goes wrong

- **Step 1 or 2**: plans change nothing. Fix and plan again.
- **Step 3 misbehaves**: forgetting only edits TFC's state, and TFC keeps every
  state version. Carry on with step 4 (it adopts everything), or revert
  rtrox/terraform-record#68 and adopt the objects back in terraform-record with `import` blocks
  by the same IDs; that plan must be imports only. Never edit state by hand.
- **Step 4 fails partway**: the imports that finished are in state. Plan,
  check and apply again; the rest are still imports.
- **Something destroyed or created**: nothing here plans either, the checker
  fails on both, and every group and client has `prevent_destroy`. Stop and
  look.

## CI

`ci-skip` keeps CI off this stack. Swapping it for `ci-apply` needs
`POCKETID_API_TOKEN` in `tf-at-home/ci` and `ci-apply`. pocket-id's API keys
have no scopes, so the `ci` one, read by every PR plan job, would be an admin
key too. Decide that first: e.g. keep plans on the laptop, or accept it.

State uses the shared passphrase. It holds no secret now (every
`client_secret` is null), but phase 3's rotations put client secrets in it;
consider `laptop-only` or narrowing who can decrypt before then.
