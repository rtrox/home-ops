# Bootstrapping

## Creating a new SOPS Age Secret

```bash
cat bitty.agekey | kubectl -n flux-system create secret generic sops-age --from-file=age.agekey=/dev/stdin --dry-run=client -o yaml
```

(Make sure the public key finds it's way into [.sops.yaml](../../../.sops.yaml))
