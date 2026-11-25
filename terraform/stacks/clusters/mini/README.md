# clusters/mini

What mini needs from outside the cluster to boot and run: its API DNS
records, its Cloudflare Tunnel and the tunnel's credentials, and the B2
buckets for volsync and the CNPG off-site copy, with the Doppler secrets the
cluster's ExternalSecrets read from `k8s-at-home/min`. Moved from
terraform-record's `cloudflare` and `backblaze` stacks in migration P2-3.
The backups of the root of trust and mini's controller tokens live in
`foundation`.

## Before tagging this stack ci-apply

The stack is tagged `ci-skip`, which keeps CI off it. The PR that swaps it for `ci-apply` needs
CI to plan it with read-only credentials, and to apply it with
`tf-at-home/ci-apply`:

| For CI | Plan (`ci`) | Apply (`ci-apply`) |
| --- | --- | --- |
| Cloudflare | `CLOUDFLARE_MINI_TOKEN` = the read-only CI token, plus an account-level `Cloudflare Tunnel Read` on `ci_readonly` | `CLOUDFLARE_MINI_TOKEN` = the real token (foundation adds the `doppler_secret` then, not before: every ci-apply job downloads the whole config) |
| B2 | `BACKBLAZE_APPLICATION_KEY_ID`/`_KEY`: a hand-made read-only key (`listBuckets`, `readBuckets`, `listKeys`, and whatever reading file-lock settings needs), no file reads | a key that can create keys on these two buckets (`writeKeys` is account-wide in B2, so this is effectively the provider key; decide then) |
| Doppler | `DOPPLER_MINI_CI_WRITE_TOKEN`, a read token on `min-ci` (below) | the same key, a write token on `min-ci` |

**Doppler: `k8s-at-home/min-ci`.** A read token on `k8s-at-home/min` would
read every secret of every app in mini, and every PR plan job reads `ci`.
So the line is: a secret written by a stack CI plans goes to `min-ci`, an
environment of its own (not a branch of `min`, which would inherit its
secrets). Foundation made it, with one token per consumer under
`DOPPLER_MINI_CI_WRITE_TOKEN`: read-only in `tf-at-home/ci`, read/write in
`ci-apply` and `prd`. This stack's new secrets are written there.

The secrets that exist today (this stack's and foundation's two mini
writes) stay in `min` for now and move later, each as its own plan-checked
step: write it to `min-ci`, then set a reference in `min` (`${min-ci.KEY}`;
references are on Doppler's free plan, config inheritance isn't), check the
cluster Secret is unchanged (compare a hash of its value before and after),
then forget and re-import at the new address.

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
