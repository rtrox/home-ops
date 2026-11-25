# curt

Storage and domains for [curt](https://github.com/rtrox/curt), a URL shortener on Cloudflare
Workers: its D1 database and KV namespace (both with `prevent_destroy`), and the
hostnames its Workers answer on. Wrangler declares no routes or domains.

Applied from the laptop (`ci-skip`), after `foundation`, which makes its
Cloudflare token:

```sh
task tf:apply STACK=curt
```

The outputs are the two IDs curt's Wrangler configuration needs (it also needs
the Cloudflare account ID).

## Tokens

Foundation's `curt_tokens.tf` makes two, in Doppler `tf-at-home/prd`:

| Key | For | Reaches it |
| --- | --- | --- |
| `CLOUDFLARE_CURT_TOKEN` | this stack | `task tf:*` |
| `CURT_ANALYTICS_CLOUDFLARE_TOKEN` | the admin Worker's `AE_TOKEN` | by hand, as a Worker secret |

The first is reissued every 90 days by a foundation apply. The second is copied
by hand, so it only changes on purpose:
`task tf:apply STACK=foundation -- -replace=cloudflare_api_token.curt_analytics`.
That deletes the old token, so metrics stop until the new one is copied.

There is no deploy token: a token that can deploy a Worker can bind any R2
bucket to it, `tofu-state` included. Deploy from the laptop (`wrangler login`).

pocket-id's client and groups are in `clusters/mini-services`. The zones (trx.fm,
rmt.dev, trxl.ink), their WAF and rate-limit rules and DNSSEC are the `dns`
stack's. Adding a short domain takes four places: `custom_domains` here,
`curt_zones` in foundation, `short_links = true` in the dns stack's
`zones.tf`, and curt's `DOMAINS` setting.
