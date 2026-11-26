# clusters/mini-services

pocket-id's groups and OIDC clients. The groups and the older clients are
hand-written in `pocketid.tf`. New clients are declared
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
- Deleting a hand-written client's entry in `pocketid.tf` works the same way,
  except that its Doppler secret is hand-set: delete that too.
- Flipping `public` replaces the client (a destroy, so also gated): pocket-id
  makes a secret only when it creates the client, so an in-place change to
  confidential would have none. The app gets a new client id and secret.
  If that apply fails after the marker updates but before the client is
  replaced, the next plan shows nothing to replace: `tofu taint` the client.
- Terraform refuses to write a Doppler secret when pocket-id has no client secret
  (an imported client, say). Replace the client (taint it, or change `public`
  and back) so pocket-id makes one.
- Changing a callback, group or name updates the client in place.

## Recovery: a client deleted in pocket-id's UI

The next plan fails reading it (404). Forget it from the state, from the
laptop (`tofu state rm 'pocketid_client.infra["<app>"]'`), then merge any change
to re-plan: the client is created again with a new id and secret, and Doppler
is updated.

## Moving a client from pocketid.tf to infra.yaml
The hand-written clients' secrets were set by hand and aren't in state. Moving
one to infra.yaml replaces it with a new client whose secret this stack writes.
In one PR:

1. Delete the app's entry from `local.clients` in `pocketid.tf`.
2. Add the app's `infra.yaml` with the same callback, groups and name.
3. Point the ExternalSecret's `<APP>_POCKETID_CLIENT` entry at `doppler-ci` (a
   per-entry `sourceRef.storeRef`, so the app's other keys stay on `doppler`),
   and add `external-secrets-store-doppler-ci` to the app's `ks.yaml`
   `dependsOn`.

The plan creates the new client and its Doppler secret and destroys the old
client, so the apply waits in `tofu-apply-gated`. Until it runs, the
ExternalSecret errors and keeps the old Secret, so the app keeps working. Once
approved, logins fail from the old client's delete until the Secret refreshes
(force it with `kubectl -n <ns> annotate externalsecret <name>
force-sync=$(date +%s) --overwrite`) and the app restarts. After a successful
login, delete the old `<APP>_POCKETID_CLIENT` from `k8s-at-home/min`.

An app configured in its own UI (shelfmark) needs the new id and secret
entered there by hand. Settings made in pocket-id's UI that the provider
doesn't manage (a logo, a launch URL) aren't carried over.
