# Per-Runner Identity — GCP

One Google service account per runner deployment, bound to that runner's
Kubernetes service account through Workload Identity, with Secret Manager access
granted **one secret at a time**.

The GCP member of a three-cloud set — see
`modules/azure/runner-identity/readme.md` for the shared rationale and the
comparison table.

## Why

`modules/gcp/gke` grants `roles/secretmanager.secretAccessor` at the **project**
level, so every runner in the project can read every secret in it. That is fine
for one tenant and unacceptable once a second business unit's credentials live
in the same project.

## Requirements

**Workload Identity must be enabled on the cluster and the node pool.** The
cluster needs `workload_identity_config`, and each node pool needs
`workload_metadata_config { mode = "GKE_METADATA" }`. A pool without it falls
back to the node service account, so pods silently run with the node's
permissions instead of the identity configured here — more access than intended,
and no error.

## Usage

```hcl
module "runner_identity_grid" {
  source = "../../modules/gcp/runner-identity"

  name       = "grid"
  project_id = var.project_id

  namespace                          = "bu-grid"
  service_account_name               = "runner-grid-sa"
  script_runner_service_account_name = "runner-grid-script-runner-sa"

  # Exactly what this tenant may read. Nothing else in the project is reachable.
  secret_ids = [
    "grid-snowflake-password",
    "grid-oauth-client-secret",
  ]

  storage_bucket_names = ["matillion-staging-grid"]
}
```

Feed the outputs into the tenant's Helm values:

```yaml
serviceAccount:
  name: runner-grid-sa      # module.runner_identity_grid.k8s_service_account_name
gcp:
  workloadIdentity:
    enabled: true
    serviceAccountEmail: "<email>"  # module.runner_identity_grid.service_account_email
```

`serviceAccount.name` in the Helm values and `service_account_name` here must be
identical — the Workload Identity binding names that exact member.

`name` is truncated to 30 characters to fit the service account ID limit, so
keep tenant prefixes short enough to stay distinct after truncation.

## Verifying the isolation

Test what the runner *cannot* read. From a runner pod in one tenant's namespace:

```bash
# Should succeed — granted to this runner.
gcloud secrets versions access latest --secret=grid-snowflake-password

# Should fail with PERMISSION_DENIED.
gcloud secrets versions access latest --secret=retail-snowflake-password
```

A `PERMISSION_DENIED` on the second command is the result you want. If it
succeeds, check whether a project-level `secretmanager.secretAccessor` grant is
still in place from `modules/gcp/gke` — a broader grant elsewhere silently
overrides the narrow one here.

## Escape hatch

`grant_project_wide_secret_access` restores project-wide read for deployments
that create secrets at runtime and cannot enumerate them at plan time. It gives
up the isolation this module exists to provide, so the `scoped_secret_ids`
output says so explicitly when it is on.
