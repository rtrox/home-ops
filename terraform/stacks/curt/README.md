# curt

Storage for [curt](https://github.com/rtrox/curt), a URL shortener on Cloudflare
Workers: its D1 database and KV namespace. Both have `prevent_destroy`.

Applied from the laptop (`ci-skip`), after `foundation`, which makes its
Cloudflare token:

```sh
task tf:apply STACK=curt
```

The outputs are the two IDs curt's Wrangler configuration needs.

## Tokens

Foundation's `curt_tokens.tf` makes three, each in Doppler `tf-at-home/prd`:

| Key | For | Reaches it |
| --- | --- | --- |
| `CLOUDFLARE_CURT_TOKEN` | this stack | `task tf:*` |
| `CURT_DEPLOY_CLOUDFLARE_TOKEN` | Wrangler in curt's GitHub Actions | by hand, as a GitHub secret there |
| `CURT_ANALYTICS_CLOUDFLARE_TOKEN` | the admin Worker's `AE_TOKEN` | by hand, as a Worker secret |

The first is reissued every 90 days by a foundation apply. The other two are
copied by hand, so they only change on purpose: replace the token in foundation
(`tofu apply -replace`), then copy the new value before anything else needs it.

pocket-id's client and groups are in `clusters/mini-services`. The trx.fm zone,
its WAF rules and DNSSEC are the `dns` stack's.
