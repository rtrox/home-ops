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
in `min`, then check the cluster Secret is unchanged (compare a hash of its value before and after),
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
