# Runner in an existing GKE cluster

Puts one Matillion runner into a GKE cluster you already run, next to any other runners there. The cluster itself is left alone. Each runner gets these, named after the runner:

- **Namespace and service accounts:** names for a namespace, a runner service account and a script runner service account. Terraform doesn't create these: the runner chart does, when you install it with the outputs below. With `serviceAccount.create=false`, create them yourself under these names.
- **Google service accounts:** one for the runner (`<name>-runner`) and one for the script runner (`<name>-scripts`), each bound through Workload Identity to its own Kubernetes service account and nothing else. The script runner runs code people write, so its account has the runner's buckets and no secrets.
- **Secrets:** the runner can read and update only secrets whose IDs start with `matillion_<name>_`. It can create and list secrets anywhere in the project; see [Secrets](#secrets).
- **GCS:** access to the buckets you list in `storage_bucket_names`.

To create a new cluster for the runner instead, use [`../gke`](../gke/).

## Before you start

- **Workload Identity must be on, for the cluster and its node pools.** The cluster needs workload pool `<project_id>.svc.id.goog`; without it, plan stops at the cluster lookup. Each node pool the runner uses needs the GKE metadata server (`--workload-metadata=GKE_METADATA`), or the pods run as the node's service account instead, with no error. Autopilot clusters have both.
- **The runner needs its own Matillion registration.** Register the runner in Matillion first, so it has its own client ID and secret.

## Deploy

```bash
cp terraform.tfvars.example terraform.tfvars  # set name, project_id, location and cluster_name
terraform init
terraform apply
```

Then install the chart into the runner's namespace with the outputs, as in [Shared Multi-Tenant Platform](../../helm/README.md#shared-multi-tenant-platform):

```bash
helm install "$(terraform output -raw namespace)" ../../helm/runner \
  --namespace "$(terraform output -raw namespace)" --create-namespace \
  -f ../../helm/runner/values-gcp.yaml \
  -f my-runner-values.yaml \
  --set dpcAgent.dpcAgent.env.defaultGcpProject="$(terraform output -raw project_id)" \
  --set serviceAccount.name="$(terraform output -raw service_account_name)" \
  --set gcp.workloadIdentity.serviceAccountEmail="$(terraform output -raw service_account_email)" \
  --set scriptRunner.serviceAccount.name="$(terraform output -raw script_runner_service_account_name)" \
  --set scriptRunner.serviceAccount.serviceAccountEmail="$(terraform output -raw script_runner_service_account_email)"
```

- `values-gcp.yaml` sets `cloudProvider: gcp`. Without it the chart adds no `iam.gke.io/gcp-service-account` annotation, and the runner gets no GCP credentials.
- `my-runner-values.yaml` holds the runner's own credentials and IDs, as in [`values-tenant-example.yaml`](../../helm/runner/values-tenant-example.yaml).
- `defaultGcpProject` is the project the runner keeps its secrets in. Matillion offers other projects too, but this root grants nothing in them.

If the cluster's Prometheus scales runners, add the namespace to its `scrapeNamespaces` and `networkPolicy.additionalScrapeNamespaces`. Otherwise the runner never scales beyond its minimum, and nothing logs why. The helm README's "Wiring the shared Prometheus" section shows how.

## Secrets

A secret the runner reads or updates must have an ID starting with `secret_name_prefix` (`matillion_<name>_`). That covers secrets created in Matillion, and secrets holding OAuth tokens the runner refreshes. Anything else is refused with a `PERMISSION_DENIED` error naming the secret. Secret IDs allow only letters, digits, `-` and `_`, so the prefix ends in `_`, and runner names never contain `_`: `matillion_fin_` can't match `matillion_fin-ops_`.

The prefix is an IAM condition on `resource.name`, and IAM checks creating and listing secrets against the project rather than the secret. So neither can be limited to the prefix, and the runner can, anywhere in the project:

- **list** every secret with its metadata (name, labels, annotations, replication, expiry, rotation and notification settings), but no value;
- **create** a secret with any ID. It gets no access to one outside its prefix, but it could create one under another runner's prefix before that runner does, with settings it chose, such as an expiry. The other runner then saves into it, or gets "already exists".

Because creating comes before adding the value, a save under a name outside the prefix fails after the secret is created, and leaves it behind empty.

Keep sensitive information out of secret labels and annotations in a shared project. Where one runner pre-creating another's secrets matters, give each runner its own project: the project is the only boundary GCP enforces on creating secrets.

The prefix keeps runners from this root apart. A runner deployed with [`../gke`](../gke/) in the same project can read every secret in it, these included.

## Custom roles

Each runner uses two custom roles in the project, one for its prefix and one for creating and listing secrets. GCP allows 300 custom roles per project, so a project holds about 150 runners, fewer if it has other custom roles.

After `terraform destroy`, a runner's custom role IDs stay reserved. Applying again with the same name within 7 days undeletes them. Between days 7 and 37 GCP is deleting them permanently and the IDs can't be reused, so the same name can't be deployed: use a different name or wait.

## Compared with `../gke`

- **GCS:** `../gke` creates a staging bucket and grants it, plus read access to any extra buckets. This root creates no bucket and grants read and write on the buckets you list; none by default.
- **Secret Manager:** read and update limited to the runner's prefix here; `../gke` grants reading every secret and `secrets.setIamPolicy` on the project. This root grants no `setIamPolicy`: the runner doesn't call it, and with it one runner could grant itself any secret in the project.
- **Project lookup:** `resourcemanager.projects.get` on the runner's project only, so Matillion lists it as somewhere to keep secrets; `../gke` grants `roles/browser`.
- **Script runner:** a Google service account of its own here, with no secrets; `../gke` binds the script runner to the runner's.
