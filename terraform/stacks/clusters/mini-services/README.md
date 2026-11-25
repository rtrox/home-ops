# clusters/mini-services

pocket-id's groups and OIDC clients. The groups and the older clients are
hand-written in `pocketid.tf` and can't be destroyed. New clients are declared
by the app, in `infra.yaml` (`infra.tf`).

## infra.yaml

Put `cluster-apps/mini/<namespace>/<app>/infra.yaml` next to the app's
`ks.yaml`:

```yaml
oidc:
  callback: https://app.rtrox.io/oauth/callback   # one URL, or a list of them
  groups: [family]                                # required; admins, family
  name: App                                       # optional, default: the directory name
  public: false                                   # optional; true = PKCE, no secret
```

Nothing else is accepted: an unknown key, a typo, a wrong type, YAML that
doesn't parse, an app directory not matching `^[a-z0-9-]+$`, a file at the
wrong depth, two apps with one name, or a clash with a client in `pocketid.tf`
fails the plan and names the file. (A bad file is never skipped: that would
plan the destruction of its app's client.)

On merge, CI creates the client and, for a confidential one, writes its id and
secret to Doppler `k8s-at-home/min-ci` as `<APP>_POCKETID_CLIENT` (the app
name upper-cased, `-` becoming `_`), a JSON secret with `client_id` and
`client_secret`. A public client gets no Doppler secret.

The app reads it through the `doppler-ci` store, not `doppler`:

```yaml
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: doppler-ci
  target:
    template:
      data:
        OIDC_CLIENT_ID: "{{ .client_id }}"
        OIDC_CLIENT_SECRET: "{{ .client_secret }}"
  dataFrom:
    - extract:
        key: APP_POCKETID_CLIENT
```

The Doppler secret exists only once the apply has finished, so the app's
ExternalSecret errors until then (merging the app and its infra.yaml in one PR
is fine: it retries).

## Changes and deletes

- Deleting `infra.yaml` destroys the client (and the Doppler secret), so that
  apply waits for the owner's approval in `tofu-apply-gated`.
- Flipping `public` replaces the client (a destroy, so also gated): pocket-id
  makes a secret only when it creates the client, so an in-place change to
  confidential would have none. The app gets a new client id and secret.
- Terraform refuses to write a Doppler secret when pocket-id has no client secret
  (an imported client, say). Replace the client (taint it, or change `public`
  and back) so pocket-id makes one.
- Changing a callback, group or name updates the client in place.

## Recovery: a client deleted in pocket-id's UI

The next plan fails reading it (404). Forget it from the state, from the
laptop (`tofu state rm 'pocketid_client.infra["<app>"]'`), then merge any change
to re-plan: the client is created again with a new id and secret, and Doppler
is updated.
