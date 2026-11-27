# clusters/mini

What mini needs from outside the cluster to boot and run: its API DNS
records, its Cloudflare Tunnel and the tunnel's credentials, the B2
buckets for volsync and the CNPG off-site copy, and the four Garage buckets
(below), with the Doppler secrets the cluster's ExternalSecrets read from
`k8s-at-home/min`. Moved from
terraform-record's `cloudflare` and `backblaze` stacks in migration P2-3.
The backups of the root of trust and mini's controller tokens live in
`foundation`.

## Garage buckets

`garage.tf` makes mini's four buckets on Garage (the NAS, `truenas` stack):
`k8s-rtrox-io-volsync-store`, `k8s-rtrox-io-mini-cnpg`,
`k8s-rtrox-io-mini-thanos` and `k8s-rtrox-io-mini-sure`, the MinIO buckets'
names, through the `object-store` module with `backend = "garage"`. Each has
one key, named after the bucket, with read and write on that bucket only. Each
writes `{application_key_id, application_key, endpoint, bucket, region}` to
Doppler `k8s-at-home/min` as `VOLSYNC_LOCAL_BUCKET`, `CNPG_LOCAL_BUCKET`,
`THANOS_LOCAL_BUCKET` and `SURE_LOCAL_BUCKET` (`endpoint` is
`http://s3.nas.rtrox.io:3900`, `region` is `garage`).

The owner applies them from the laptop (`task tf:apply STACK=clusters/mini`;
the stack is `ci-skip`): the garage provider reaches Garage's admin API
(`s3.nas.rtrox.io:3903`) with `GARAGE_ADMIN_TOKEN` from `hosts-at-home/prd`,
which CI's runner can't reach yet. The consumers still read the
`*_MINIO_BUCKET` keys: each moves to its `*_LOCAL_BUCKET` key in its own
cutover PR. Garage's layout isn't in Terraform (the provider's `garage_node`
fails on Garage v2.6.0), and a destroyed key can't be re-imported (Garage
keeps tombstones), so never destroy and re-create one: rotate by adding a
second key.

## Before tagging this stack ci-apply

The stack is tagged `ci-skip`, which keeps CI off it. The PR that swaps it for `ci-apply` needs
CI to plan it with read-only credentials, and to apply it with
`tf-at-home/ci-apply`:

| For CI | Plan (`ci`) | Apply (`ci-apply`) |
| --- | --- | --- |
| Cloudflare | `CLOUDFLARE_MINI_TOKEN` = the read-only CI token, plus an account-level `Cloudflare Tunnel Read` on `ci_readonly` | `CLOUDFLARE_MINI_TOKEN` = the real token (foundation adds the `doppler_secret` then, not before: every ci-apply job downloads the whole config) |
| B2 | `BACKBLAZE_APPLICATION_KEY_ID`/`_KEY`: a hand-made read-only key (`listBuckets`, `readBuckets`, `listKeys`, and whatever reading file-lock settings needs), no file reads | a key that can create keys on these two buckets (`writeKeys` is account-wide in B2, so this is effectively the provider key; decide then) |
| Doppler | `DOPPLER_MINI_CI_WRITE_TOKEN`, a read token on `min-ci` (below) | the same key, a write token on `min-ci` |
| Garage | `GARAGE_ADMIN_TOKEN` in `hosts-at-home` (read via `TF_CI_HOSTS_TOKEN`), and the runner able to reach the admin port 3903. `GARAGE_ADMIN_TOKEN` can create and delete buckets and keys, so a CI plan needs a separate read-only scoped admin token (Garage admin tokens take scopes), not this one | the same, from `ci-apply` |

**Doppler: `k8s-at-home/min-ci`.** A read token on `k8s-at-home/min` would
read every secret of every app in mini, and every PR plan job reads `ci`.
So the line is: a secret written by a stack CI plans goes to `min-ci`, an
environment of its own (not a branch of `min`, which would inherit its
secrets). Foundation made it, with one token per consumer under
`DOPPLER_MINI_CI_WRITE_TOKEN`: read-only in `tf-at-home/ci`, read/write in
`ci-apply` and `prd`. This stack's new secrets are written there.

foundation, which CI never plans, keeps writing its mini secrets to `min`.

Phase 3 replaces this line with a split by purpose: `kubernetes` holds app
secrets and `kubernetes-platform` what the cluster runs on, this stack's
included, and CI gets a token for each. If the stack goes into CI before that,
its existing secrets move to `min-ci` first, in the order below. After the
split, the same order moves each secret to its project instead, and the
reference in step 3 names the project too. Either way, one secret at a time
(any other order has Terraform overwrite or delete the live value, or the
cluster read a dangling reference):

1. Write the current value to `min-ci` by hand (Doppler).
2. Forget the old `doppler_secret` from this stack's state (`removed` block
   with `destroy = false`), so Terraform never touches the one in `min`
   again. Plan-check that it's a forget, not a destroy.
3. Only then set the reference in `min` (`${min-ci.KEY}`; references are on
   Doppler's free plan, config inheritance isn't), and check the cluster
   Secret is unchanged (compare a hash of its value before and after).
4. Import the `min-ci` secret at its new address.

The cluster reads `min-ci` through a second ClusterSecretStore, `doppler-ci`,
with its own read-only token, so the existing `doppler` store keeps reading
`min`.

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
