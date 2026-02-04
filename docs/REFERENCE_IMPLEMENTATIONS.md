# Working with Reference Implementations

> Guide for extracting patterns from external repositories and adapting them to home-ops

When implementing applications based on external references (e.g., kubesearch.dev, awesome-home-kubernetes, bjw-s-labs/home-ops, other GitOps repos), follow this process to avoid common mistakes.

## Common Sources

- **kubesearch.dev**: Search engine for Kubernetes manifests in public repos
- **awesome-home-kubernetes**: Curated list of home lab k8s resources
- **bjw-s-labs/home-ops**: Reference implementations using bjw-s app-template chart
- **onedr0p/home-ops**: Another popular home lab reference
- **Application documentation**: Official Helm charts and manifests

## Critical Understanding

**Reference implementations are examples from OTHER environments** - they use:

- Different NAS servers and paths
- Different secret management (1Password, SOPS, Vault)
- Different ingress/gateway configurations
- Different cluster patterns and conventions

**Your job: Extract patterns, adapt to Chongus standards**

## Extract vs. Adapt Process

### Step 1: Initial Analysis (BEFORE Implementation)

When given a reference URL, **explicitly document**:

1. **Container Images** (extract exactly):
   ```text
   Repository: ghcr.io/booklore-app/booklore (NOT ghcr.io/bjw-s-labs/booklore)
   Tag: v1.18.5@sha256:44a39097fcf69e7373b51df0459da052640d07459fb02b429f2c47cceaa32485
   ```
   - DO NOT assume image org names from chart sources
   - Helm chart org ≠ application image org
   - Verify each container's exact repository

2. **Volume Patterns** (extract structure):
   - Mount paths and subPaths
   - emptyDir vs PVC vs NFS usage
   - Size limits and medium (Memory/default)

3. **Probe Configurations** (extract exactly):
   - Health check endpoints and ports
   - Startup/liveness/readiness settings
   - Failure thresholds and periods

4. **Security Contexts** (extract, but verify compatibility):
   - Note any `Unconfined` seccomp profiles (may conflict with PodSecurity)
   - User/group IDs
   - Capability drops

5. **Resource Limits** (extract as baseline):
   - CPU requests/limits
   - Memory requests/limits

### Step 2: Adaptation Checklist

**ALWAYS adapt these to Chongus patterns:**

- [ ] **NAS/NFS**: Change to `nas.rtrox.io` with correct paths (`/mnt/rusty/media/...`)
- [ ] **Secrets**: Replace with Doppler ExternalSecret (JSON pattern preferred)
- [ ] **Gateway**: Use `envoy-internal` unless internet access explicitly needed
- [ ] **GitRepository**: ALWAYS `flux-system` in `sourceRef`
- [ ] **Components**: Use `../../../../components/volsync` for backups
- [ ] **Namespace**: Verify PodSecurity compatibility (remove `Unconfined` if needed)
- [ ] **Dependencies**: Add `dependsOn` for `rook-ceph-cluster`, `external-secrets-store-doppler`

### Step 3: Pre-Implementation Summary

Before writing any code, provide a summary like:

```text
## Reference Analysis: Booklore from bjw-s-labs

### Extracting Exactly:
- Image: ghcr.io/booklore-app/booklore:v1.18.5@sha256:44a39...
- MariaDB: mariadb:12.1.2-noble@sha256:f54db0...
- Nginx structure: single emptyDir, multi-path mounts
- Probes: /api/v1/healthcheck on port 8080

### Adapting to Chongus:
- NFS: nas.rtrox.io:/mnt/rusty/media/books (vs gladius.bjw-s.internal)
- Secrets: Doppler ExternalSecret with BOOKLORE key (vs 1Password)
- Gateway: envoy-internal (vs their ingress)
- Remove: seccompProfile Unconfined (conflicts with default namespace PodSecurity)
```

## Common Mistakes to Avoid

1. **Wrong Image Repository**
   - ❌ Assuming `ghcr.io/bjw-s-labs/[app]` because bjw-s uses bjw-s chart
   - ✅ Extract exact repository: `ghcr.io/booklore-app/booklore`

2. **Copying Storage Paths**
   - ❌ Using their NFS server: `gladius.bjw-s.internal:/mnt/tank/media`
   - ✅ Adapt to yours: `nas.rtrox.io:/mnt/rusty/media/books`

3. **Copying Secret Patterns**
   - ❌ Using their 1Password ExternalSecret config
   - ✅ Convert to Doppler with JSON key pattern

4. **Skipping Security Validation**
   - ❌ Copying `seccompProfile: Unconfined` without checking
   - ✅ Test against namespace PodSecurity policy first

5. **Wrong GitRepository**
   - ❌ Seeing `home-ops` in their config and using it
   - ✅ Always use `flux-system` in your cluster

## Example Workflow

```bash
# User provides reference
"Use this as reference: https://github.com/bjw-s-labs/home-ops/tree/main/kubernetes/apps/media/booklore"

# AI Analysis (BEFORE coding)
1. Fetch helmrelease.yaml
2. List all container images with EXACT repos/tags/digests
3. Document volume patterns and mount paths
4. Note probe endpoints and security contexts
5. Create Extract vs Adapt summary
6. Ask for confirmation or clarification

# User confirms or provides NFS paths, secrets, gateway choice

# AI Implementation
1. Create files following Chongus structure
2. Use extracted images/probes/volumes exactly
3. Adapt NFS/secrets/gateway to Chongus
4. Run flux-local test for validation
5. Fix any issues (PodSecurity, paths, etc.)
```

## Validation After Implementation

- [ ] `flux-local test` passes
- [ ] All images verified (not assumed from chart org)
- [ ] NFS paths point to `nas.rtrox.io`
- [ ] Secrets reference Doppler
- [ ] Gateway uses correct endpoint
- [ ] No PodSecurity violations
- [ ] GitRepository is `flux-system`

## When to Ask for Clarification

- Multiple valid NFS path options (ask user)
- Choice between envoy-internal vs envoy-external (ask user)
- Uncertain about secret structure (ask if JSON key exists in Doppler)
- Security context conflicts (ask if privileged namespace acceptable)
- Missing probe endpoints in reference (ask or research application docs)
