# clusters/mini-services

pocket-id's groups and OIDC clients. The groups and the nine older clients are
hand-written in `pocketid.tf` and can't be destroyed. New clients are declared
by the app, in `infra.yaml`.

## infra.yaml

Put `cluster-apps/mini/<namespace>/<app>/infra.yaml` next to the app's
`ks.yaml`:

```yaml
oidc:
  callback: https://app.rtrox.io/oauth/callback   # one URL, or a list
  groups: [family]                                # required; admins, family
  name: App                                       # optional, default: the directory name
  public: false                                   # optional; true = PKCE, no secret
```

The directory name is the app's key: it must be unique across namespaces and
must not be one of the hand-written clients. A bad file fails the plan with a
message naming it (unknown group, no callback, no groups, a duplicate app, or
a clash with `pocketid.tf`).

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

Deleting `infra.yaml` destroys the client (and its login), so that apply waits
for the owner's approval in `tofu-apply-gated`. Changing a callback or group
changes the client in place.
