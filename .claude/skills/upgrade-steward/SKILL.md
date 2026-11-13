---
name: upgrade-steward
description: Review open dependency-update PRs for the Mini cluster, decide which are low-risk enough to merge, and (in merge mode) merge one at a time, soak the rollout, and roll back with a revert PR if it misbehaves. Use for the scheduled upgrade run or when asked to triage/merge update PRs.
---

# Upgrade steward

Triage the open Renovate PRs in `rtrox/home-ops`, merge only what clears the
risk bar, watch each rollout, and roll back on evidence. Everything is
conservative by design: when unsure, hold the PR and say why.

## Modes

The prompt says which mode to run. Default to **dry-run** if it does not.

- **dry-run**: review and classify every PR, write the report, change nothing.
  Do not merge, close, comment on, label, push, or revert anything.
- **merge**: as dry-run, then merge Tier-0 PRs one at a time with a soak, and
  roll back with a revert PR if the soak fails. Tier 1 is report-only unless the
  prompt says `TIER1=merge`.

## Command style (the run is permission-gated; unlisted commands are denied)

- One simple command per Bash call. No `&&`, `;`, subshells or heredocs. Pipes
  into `jq`, `grep`, `awk`, `sort`, `head`, `tail`, `wc` are fine.
- Put the kubectl verb first: `kubectl get pods -n <ns>`, never
  `kubectl -n <ns> get pods` (the allowlist matches on the verb prefix).
- Read-only only: `kubectl get|describe|logs|top`, `flux get`, `gh pr|release|search`,
  `git fetch|log|diff|show`, `helm pull|show|template`. Everything else is denied;
  do not look for a workaround, report it and stop that step.
- If a denial blocks a required check, abort the run and say exactly which command
  and why it was needed.

## Hard rules

- Public repo: never name specific trackers anywhere (PRs, comments, commits).
- Never print, read, or write secrets. Never `kubectl get secret(s)`. Never touch
  Doppler. Describe secret-related changes without values.
- Cluster access is read-only. Roll back only with a `git revert` PR, never by
  editing live objects.
- Report times in Pacific.
- Commits and PR bodies carry the attribution lines from the session reminder.
- One merge at a time. At most **3 merges per run**. Stop on the first failed
  soak; do not merge anything else that run.
- Never merge a draft PR, a PR labelled `hold`, or any PR that is Tier 2.
- Never merge when preflight fails.

## Preflight (abort the whole run if any fails)

1. `git fetch origin`; work from `origin/main` state. `gh auth status` works.
2. Cluster reachable (`kubectl get nodes`), all nodes Ready, K8s version noted.
3. `flux get hr -A` and `flux get ks -A`: nothing not Ready.
4. Ceph HEALTH_OK: `kubectl get cephcluster -n rook-ceph -o jsonpath='{.items[0].status.ceph.health}'`
   (never `kubectl exec`).
5. No Talos/K8s upgrade in progress (TalosUpgrade/KubernetesUpgrade not running).
6. Record the **baseline**: firing alerts (name + labels) from Prometheus via the
   API-server proxy, and the set of non-Ready pods. Alerts already firing at
   baseline are not counted against a change (e.g. alerts about remote hosts).
   Abort (merge mode) if any **critical** alert is firing.
7. Read any pending-work notes in
   `~/.claude/projects/-home-rtrox-home-ops/memory/` (especially the upgrade-round
   file) for dated holds and revisit dates; honor them.

## Classify every open PR

Gather: `gh pr list --state open --json number,title,labels,isDraft,files,headRefName`.
Then assign a tier from the **highest** applicable rule.

**Tier 2: never auto-merge (review comment/report only)**
- Title has `!`, or the update is a major.
- Any file under `clusters/`, `ansible/`, `.github/`, `.taskfiles/`, `docs/`, or
  `.archive/`.
- Namespaces: `kube-system`, `system`, `network`, `rook-ceph`, `database`,
  `observability`, `external-secrets`, `cert-manager`, `flux-system`,
  `system-upgrade`, and anything of the steward itself.
- Packages: Talos, Kubernetes, Cilium, Rook/Ceph, CloudNativePG and its plugin,
  Envoy Gateway, Gateway API, CoreDNS, kube-prometheus-stack, Prometheus
  operator/CRDs, external-secrets, cert-manager, Flux, volsync, tuppr, Reloader,
  KEDA, node-feature-discovery, NVIDIA device plugin.
- The PR changes CRDs, a StatefulSet's volumeClaimTemplates, or storage classes.
- The app runs migrations that cannot be undone by rolling the image back (an
  app with a `Database` CR in `database/cloudnative-pg/cluster`, or anything the
  release notes say migrates data on first start).
- Draft PR, `hold` label, or a dated hold in the notes.

**Tier 1: report-only unless `TIER1=merge`**
- Minor bumps of apps in `default` (or similar app namespaces) that are not Tier 2.
- Chart bumps where the rendered template diff touches nothing we set in values.

**Tier 0: merge candidates (merge mode)**
- Patch, pin, and digest bumps of apps outside Tier 2, in app namespaces, with
  green CI and a clean review (below).

## Review checklist (every Tier 0/1 PR; Tier 2 gets a report-only version)

Renovate's PR body release notes are frequently for the wrong release or empty.
Do not trust them. Verify instead:

1. CI: `gh pr checks <n> --json state,name`. Treat SKIPPED as not-a-failure; any
   FAILURE or non-terminal state means hold. `mergeStateStatus` must be CLEAN.
2. Identify what actually changes: image tag/digest, or chart version. For a
   chart, `helm pull` both versions into a temp dir and diff `Chart.yaml`
   (appVersion), `values.yaml`, `templates/`, and `crds/`. Note any default that
   changed which we do not override.
3. Read the upstream release notes for the **real** version(s) (`gh release view`
   on the upstream repo, or the upstream changelog/upgrade doc). Flag: breaking,
   removed, renamed, migration, deprecat, security, "requires", database/schema.
4. Compare with our config: grep the HelmRelease/values for anything the change
   touches (env vars, flags, routes, ports, security context, resource limits).
5. Check repo rules the PR must not violate (image digest pinned, memory limits).
6. Any breaking-change flag, schema/data migration, or unclear compatibility:
   escalate to Tier 2 and say why.

Output for each PR: number, title, tier, decision (merge / hold / report), the
two or three facts that decided it, and what would change the decision.

## Merge and soak (merge mode only, Tier 0, one at a time)

1. Re-check baseline is still clean; re-check CI and `mergeStateStatus`.
2. Record pre-merge: affected Flux objects, deployed image/chart, pod names.
3. `gh pr merge <n> --squash`; note the merge commit SHA and time.
4. `flux reconcile source git flux-system`; wait for the affected HelmRelease or
   Kustomization to report the new revision and Ready (bounded loop, give up
   after 10 minutes).
5. **Soak for 10 minutes**, checking every ~60 seconds (use a bounded loop; do
   not chain long foreground sleeps). Fail the soak on any of:
   - affected HelmRelease/Kustomization not Ready after reconcile;
   - any affected pod not Ready, or a restart/OOMKilled/CrashLoopBackOff;
   - a **new** firing alert compared with baseline;
   - any HTTPRoute hostname of the app returning a 5xx or no response
     (`curl -sk -o /dev/null -w '%{http_code}'`);
   - the app's own health endpoint, if it has one, not OK.
6. Pass: log it and move to the next candidate. Fail: roll back.

## Roll back (merge mode only)

1. `git checkout -b revert/pr-<n> origin/main`; `git revert --no-edit <merge sha>`.
   Commit message states what failed (evidence, no secrets) plus attribution.
2. Push, open a PR titled `revert: <original title>`, wait for CI, merge it.
3. Wait for the Flux object to return to the previous revision and Ready; confirm
   pods healthy and the baseline alert set restored.
4. Comment on the original PR with the evidence, and record the package/version in
   `~/.local/state/upgrade-steward/held.json` so it is not retried automatically.
5. If the rollback itself does not recover the cluster, stop, change nothing else,
   and put it at the top of the report as URGENT with the exact state.

A revert does not undo CRD updates or data migrations, which is why those are
Tier 2. If a failed Tier-0 PR turns out to have done either, say so loudly.

## State and report

- State dir: `~/.local/state/upgrade-steward/` (the task creates it; do not run
  `mkdir`). Write
  `runs/<YYYY-MM-DD-HHMM>.md` for every run; keep `held.json` for rolled-back
  versions and skip any PR whose version is listed there.
- Final output is the report, in this order: URGENT items; merged (with soak
  result); rolled back; held (Tier 2) with the reason and what to check; Tier 1
  report-only candidates; skipped PRs. Keep it short and specific. Times in Pacific.
- In dry-run, also state which PRs **would** have been merged.
