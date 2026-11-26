# GCP GKE Deployment for Matillion Runner

This directory contains Terraform configurations for deploying the Matillion Maia Runner using Google Kubernetes Engine (GKE) — Google Cloud's managed Kubernetes service.

To put a runner into a GKE cluster you already run, beside other runners, use [`../gke-existing-cluster`](../gke-existing-cluster/) instead. Each runner gets its own namespace, Google service accounts and secrets prefix, and the cluster is left alone.

## Overview

GKE deployment provides:
- **Managed Kubernetes Control Plane**: Google handles the API server, etcd, and control-plane components
- **Workload Identity**: Keyless authentication from pods to GCP services (Secret Manager, GCS)
- **Auto-scaling**: Horizontal Pod Autoscaler (HPA) and cluster autoscaler on the node pool
- **Private Nodes**: Nodes with no external IPs, egress via Cloud NAT
- **Google Cloud Monitoring**: Native integration with Cloud Logging and Cloud Monitoring

## Architecture

```
┌───────────────────────────────────────────────────────────────────┐
│                         GCP Project                               │
│  ┌──────────────────────────────────────────────────────────────┐ │
│  │                      GKE Cluster                             │ │
│  │  ┌─────────────────────────────────────────────────────────┐ │ │
│  │  │                 Control Plane                           │ │ │
│  │  │           (Managed by Google)                           │ │ │
│  │  └─────────────────────────────────────────────────────────┘ │ │
│  │  ┌─────────────────────────────────────────────────────────┐ │ │
│  │  │                  Node Pool                              │ │ │
│  │  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │ │ │
│  │  │  │   Node 1    │  │   Node 2    │  │   Node N    │     │ │ │
│  │  │  │ ┌─────────┐ │  │ ┌─────────┐ │  │ ┌─────────┐ │     │ │ │
│  │  │  │ │ Runner  │ │  │ │ Runner  │ │  │ │ Runner  │ │     │ │ │
│  │  │  │ │   Pod   │ │  │ │   Pod   │ │  │ │   Pod   │ │     │ │ │
│  │  │  │ └─────────┘ │  │ └─────────┘ │  │ └─────────┘ │     │ │ │
│  │  │  └─────────────┘  └─────────────┘  └─────────────┘     │ │ │
│  │  └─────────────────────────────────────────────────────────┘ │ │
│  └──────────────────────────────────────────────────────────────┘ │
│  ┌──────────────────────────────────────────────────────────────┐ │
│  │                    Supporting Services                       │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐          │ │
│  │  │   Secret    │  │     GCS     │  │   Cloud     │          │ │
│  │  │  Manager    │  │   Bucket    │  │  Monitoring │          │ │
│  │  └─────────────┘  └─────────────┘  └─────────────┘          │ │
│  └──────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────┘
```

## Prerequisites

### Required Tools
- [Terraform 1.0+](https://www.terraform.io/downloads.html)
- [Google Cloud SDK (`gcloud`)](https://cloud.google.com/sdk/docs/install) configured with appropriate permissions
- [kubectl](https://kubernetes.io/docs/tasks/tools/) for cluster management
- [Helm 3.0+](https://helm.sh/docs/intro/install/) for application deployment

### GCP Project Requirements
- Valid GCP project with billing enabled
- The following APIs enabled:
  ```bash
  gcloud services enable container.googleapis.com
  gcloud services enable compute.googleapis.com
  gcloud services enable secretmanager.googleapis.com
  gcloud services enable storage.googleapis.com
  gcloud services enable iam.googleapis.com
  gcloud services enable cloudresourcemanager.googleapis.com
  ```

### Required GCP Permissions

```bash
# Authenticate with GCP
gcloud auth application-default login

# Verify identity
gcloud auth list
```

Required IAM roles for the Terraform runner:
- `roles/container.admin` — GKE cluster management
- `roles/compute.networkAdmin` — VPC and subnet management
- `roles/iam.serviceAccountAdmin` — Service account creation
- `roles/iam.serviceAccountKeyAdmin` — Workload Identity bindings
- `roles/storage.admin` — GCS bucket management
- `roles/secretmanager.admin` — Secret Manager management
- `roles/resourcemanager.projectIamAdmin` — IAM bindings
- `roles/iam.roleAdmin` — Custom role creation (`runner_secret_creator`)
- `roles/iam.serviceAccountUser` (`iam.serviceAccounts.actAs`): lets the cluster and its node pools run as the node service account. The default compute service account is not used. When the module creates the node service account, that account does not exist before the first apply, so grant this role at project level. To grant it on a single account instead, pre-create the node service account (see [Pre-creating the node service account](#pre-creating-the-node-service-account)).

#### Deploying with pre-created accounts

When an IAM admin pre-creates the node service account, the runner service
account and the runner secret creator role, and the deployment sets
`existing_node_service_account_email`,
`existing_runner_workload_service_account_email`,
`existing_runner_secret_creator_role_id` and `grant_node_project_roles = false`,
Terraform makes no project-level IAM change. The deployer then needs:

- on the project: `roles/container.admin`, `roles/compute.networkAdmin`,
  `roles/storage.admin` and `roles/secretmanager.admin`;
- on the node service account only: `roles/iam.serviceAccountUser`;
- on the runner service account only: a role holding
  `iam.serviceAccounts.getIamPolicy` and `iam.serviceAccounts.setIamPolicy`
  (for example `roles/iam.serviceAccountAdmin`), to add the Workload Identity
  members.

The deployer needs none of `roles/iam.serviceAccountAdmin`,
`roles/iam.serviceAccountKeyAdmin`, `roles/resourcemanager.projectIamAdmin`,
`roles/iam.roleAdmin` or `roles/iam.serviceAccountUser` at project level.

Two inputs still need more:

- `additional_gcp_projects`: Terraform grants the runner service account roles
  in each listed project, so the deployer needs
  `resourcemanager.projects.setIamPolicy` (for example
  `roles/resourcemanager.projectIamAdmin`) in each of those projects.
- `existing_runner_workload_service_account_email` without
  `existing_runner_secret_creator_role_id`: Terraform still creates its own
  secret creator role (needs `iam.roles.create`) and grants it to nobody. Set
  both.

### Pre-creating the runner secret creator role

By default the deployment creates a custom role, `<name>_a_<suffix>_secret_creator` (hyphens in `name` become underscores), and grants it to the runner service account. The role id changes with every deployment.

To use a fixed role instead, an IAM admin holding `roles/iam.roleAdmin` creates it once per project from [runner-secret-creator-role.yaml](runner-secret-creator-role.yaml):

```bash
gcloud iam roles create matillion_runner_secret_creator \
  --project=<your-project-id> \
  --file=runner-secret-creator-role.yaml
```

The deployment then sets, in `terraform.tfvars`:

```hcl
existing_runner_secret_creator_role_id = "projects/<your-project-id>/roles/matillion_runner_secret_creator"
```

With this set, Terraform creates no custom role and grants the given role to the runner service account, so the deployer no longer needs `iam.roles.create`. It still needs to set the project IAM policy to grant the role. Restricting the deployer's `setIamPolicy` to named roles needs an IAM condition, which is covered separately.

`terraform destroy` removes the grant and leaves the pre-created role in place. Several deployments in one project can share the role.

Do not delete and recreate the role with the same id. A deleted custom role can be undeleted for 7 days (`gcloud iam roles undelete`), and its id cannot be reused for about 37 days after deletion.

#### Upgrading: existing deployments

On an existing deployment, leaving `existing_runner_secret_creator_role_id` unset gives no plan change. The role's address moves from `module.gke.google_project_iam_custom_role.runner_secret_creator` to `module.gke.google_project_iam_custom_role.runner_secret_creator[0]`, which the plan reports as a move only.

Setting it on an existing deployment destroys that deployment's own role (GCP soft-deletes it) and replaces the binding to grant the given role. Between the two, the runner cannot create secrets, so apply when nobody is adding OAuth or cloud credentials in the Matillion UI.

## Quick Start

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd deployment-library/runner/gcp/gke
```

### 2. Enable Required APIs

```bash
gcloud services enable \
  container.googleapis.com \
  compute.googleapis.com \
  secretmanager.googleapis.com \
  storage.googleapis.com \
  iam.googleapis.com \
  cloudresourcemanager.googleapis.com \
  --project=<your-project-id>
```

### 3. Configure Variables

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

Minimum required values:
```hcl
project_id = "your-gcp-project-id"
region     = "us-central1"
name       = "matillion-runner"

labels = {
  environment = "production"
  project     = "matillion-runner"
}
```

`terraform plan` rejects values GCP would reject later during apply:

- `name`: lowercase letters, digits and hyphens, starting with a letter and ending with a letter or digit, at most 21 characters. The cluster is named `<name>-gke-cluster-<6-character suffix>`, and GKE cluster names are limited to 40 characters.
- `labels`: keys start with a lowercase letter; keys and values use only lowercase letters, digits, `_` and `-`, up to 63 characters each.
- `authorized_ip_ranges`: each entry is a CIDR block with a prefix length, for example `203.0.113.0/24`. A bare address such as `10.0.0.1` is rejected.

Upgrading: a deployment with an uppercase `name` or label already failed on GCP during apply, so no working deployment is affected by those rules. This root has no input to override resource names, so a `name` over 21 characters always produced a cluster name over 40 characters. Such a configuration now fails at plan instead of during apply, and must use a shorter `name`.

### 4. Deploy GKE Infrastructure

```bash
# Initialise Terraform
terraform init

# Review deployment plan
terraform plan

# Deploy GKE cluster and supporting infrastructure
terraform apply
```

### 5. Configure kubectl Access

```bash
# Use the command from Terraform output
terraform output -raw auth_config_command | bash

# Verify cluster access
kubectl get nodes
```

### 6. Deploy Matillion Runner with Helm

```bash
# Navigate to the Helm chart directory
cd ../../helm/runner

# Create the runner namespace
kubectl create namespace matillion

# Install using the GCP values file
helm install matillion-runner . \
  --namespace matillion \
  --values values-gcp.yaml \
  --set gcp.workloadIdentity.serviceAccountEmail="$(cd ../../../runner/gcp/gke && terraform output -raw runner_workload_sa_email)" \
  --set config.oauthClientId="<your-client-id>" \
  --set config.oauthClientSecret="<your-client-secret>" \
  --set dpcAgent.dpcAgent.env.accountId="<matillion-account-id>" \
  --set dpcAgent.dpcAgent.env.agentId="<matillion-runner-id>" \
  --set dpcAgent.dpcAgent.env.matillionRegion="<matillion-region>"
```

### 7. Verify Deployment

```bash
# Check pod status
kubectl get pods -n matillion

# View pod logs
kubectl logs -l app.kubernetes.io/name=matillion-runner -n matillion

# Check HPA status
kubectl get hpa -n matillion
```

## Configuration Options

### Agent Sizing

The runner's container resources are set on the helm chart via `runnerSize` (see `runner/helm/README.md`). The Terraform here only stands up the cluster — pick a `machine_type` large enough to host the t-shirt size you plan to install:

| Helm `runnerSize` | Pod requests | Recommended GKE `machine_type` |
|---|---|---|
| `small` | 1 vCPU / 4 GiB | `e2-standard-2` (2 vCPU / 8 GiB) |
| `medium` | 2 vCPU / 8 GiB | `e2-standard-4` (4 vCPU / 16 GiB) |
| `large` | 4 vCPU / 16 GiB | `e2-standard-8` (8 vCPU / 32 GiB) |
| `xlarge` | 8 vCPU / 32 GiB | `e2-standard-16` (16 vCPU / 64 GiB) |

Always pick a node one tier above the request — kubelet, system daemons and the metrics sidecar each need headroom or the pod stays `Pending`.

### GKE Cluster Configuration

#### Development Environment
```hcl
desired_node_count   = 2                 # per zone
machine_type         = "e2-standard-4"   # supports runnerSize=small or medium
is_private_cluster   = false
enable_cloud_nat     = false
authorized_ip_ranges = ["<your-office-ip>/32"]
```

#### Production Environment
```hcl
desired_node_count     = 3             # per zone
machine_type           = "e2-standard-8" # supports runnerSize=large
is_private_cluster     = true
enable_cloud_nat       = true          # Required for private nodes when this module creates the VPC
authorized_ip_ranges   = ["10.0.0.0/8", "203.0.113.0/24"]
master_ipv4_cidr_block = "172.16.0.0/28"
```

#### Node count

`desired_node_count` applies to each zone. The cluster and its node pool both use `location = var.region`, so the node pool runs in every zone of the region. The total number of nodes is `desired_node_count` times the number of zones, and the autoscaler range is `desired_node_count` to `desired_node_count + 2` per zone. For example, with the default of 2 in `europe-west1`, which has three zones (b, c, d), the cluster starts with 6 nodes and can grow to 12. The Production example above (3) therefore starts 9 nodes of `e2-standard-8` in a three-zone region. To run fewer nodes, lower `desired_node_count`.

### Workload Identity

GKE Workload Identity allows pods to authenticate to GCP APIs without managing service account keys. The Terraform module:

1. Creates a GCP Service Account (`runner_workload_sa`), unless `existing_runner_workload_service_account_email` names one created beforehand (see [Pre-creating the runner service account](#pre-creating-the-runner-service-account))
2. Binds it to the Kubernetes Service Account created by Helm (`matillion/matillion-runner-sa` by default, independent of `var.name`)
3. Grants the GCP SA access to Secret Manager and GCS

The Helm chart adds the required annotation to the Kubernetes Service Account:
```yaml
annotations:
  iam.gke.io/gcp-service-account: <gcp-sa-email>
```

Pass the SA email from Terraform output:
```bash
terraform output -raw runner_workload_sa_email
```

### Identity is not optional

**A GKE runner deployed outside this Terraform has no GCP identity by default.**
Nothing about the cluster grants a pod access to your project — the identity
comes from a Workload Identity binding, and that binding is created here, not by
`helm install`. Install the chart against a cluster you built by hand and the
runner starts, registers with the control plane, and then fails on its first
Secret Manager or GCS call.

This is how the 2026-08-28 GKE deployment failed: the cluster was built
manually, so there was no `runner_workload_sa_email` output to pass, and
`gcp.workloadIdentity.enabled: false` looked like the way past the resulting
Helm error. It installed cleanly and the runner had no access to the service
account or the project.

The chart now refuses that combination. With `gcp.workloadIdentity.enabled:
false` and no alternative named, rendering fails and tells you what is missing.
There is exactly one sanctioned way to install without Workload Identity:

```yaml
gcp:
  workloadIdentity:
    enabled: false
  nodeIdentity:
    enabled: true    # pod inherits the node pool's service account via IMDS
```

Take that path only deliberately. The node pool's service account is shared by
every pod on the node and is usually the default compute SA — broader than the
runner needs in some directions and, more to the point, missing the Secret
Manager and GCS grants it does need. Prefer Workload Identity.

Three things must all be true for Workload Identity to work, and the chart only
does the second:

| # | What | Who does it |
|---|---|---|
| 1 | Workload Identity enabled on the cluster **and the node pool** | Terraform (`modules/gcp/gke`) or `gcloud` |
| 2 | `iam.gke.io/gcp-service-account` annotation on the KSA | this Helm chart |
| 3 | `roles/iam.workloadIdentityUser` binding from the GCP SA to the KSA | Terraform (`modules/gcp/runner-identity`) or `gcloud` |

Any one of them missing produces the same symptom: a healthy-looking pod that
cannot reach GCP. The chart's post-install NOTES print the exact commands to
check all three.

### Binding an identity to a runner already installed

If a runner is already running without an identity, you do not need to
reinstall — bind one and restart the pods.

```bash
PROJECT=<your-project-id>
NAMESPACE=matillion-runner          # the release namespace
KSA=matillion-runner-sa             # kubectl get sa -n $NAMESPACE
GSA=matillion-runner@$PROJECT.iam.gserviceaccount.com

# 1. Workload Identity on the cluster and every node pool that runs the runner.
#    Both are required — cluster-level alone leaves the node's metadata server
#    handing out the node SA and the annotation silently ignored.
gcloud container clusters update <cluster> --project="$PROJECT" --region=<region> \
  --workload-pool="$PROJECT.svc.id.goog"
gcloud container node-pools update <node-pool> --project="$PROJECT" \
  --cluster=<cluster> --region=<region> --workload-metadata=GKE_METADATA

# 2. A GCP service account with the runner's grants.
gcloud iam service-accounts create matillion-runner --project="$PROJECT"
for ROLE in roles/secretmanager.secretAccessor roles/storage.objectAdmin; do
  gcloud projects add-iam-policy-binding "$PROJECT" \
    --member="serviceAccount:$GSA" --role="$ROLE"
done

# 3. Let the Kubernetes SA impersonate it.
gcloud iam service-accounts add-iam-policy-binding "$GSA" --project="$PROJECT" \
  --role=roles/iam.workloadIdentityUser \
  --member="serviceAccount:$PROJECT.svc.id.goog[$NAMESPACE/$KSA]"

# 4. Tell the chart about it, then roll the pods.
helm upgrade matillion-runner ../../helm/runner --namespace "$NAMESPACE" --reuse-values \
  --set gcp.workloadIdentity.enabled=true \
  --set gcp.workloadIdentity.serviceAccountEmail="$GSA"
kubectl rollout status deployment/matillion-runner-app -n "$NAMESPACE"

# 5. Confirm the pod can get a token. This is the only check that proves all
#    three layers line up. It prints the HTTP status only, never the token.
kubectl exec -n "$NAMESPACE" deploy/matillion-runner-app -- \
  curl -s -o /dev/null -w '%{http_code}\n' -H 'Metadata-Flavor: Google' \
  http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token
# must print 200

# 6. Informational: which account the pod is configured with.
kubectl exec -n "$NAMESPACE" deploy/matillion-runner-app -- \
  curl -sH 'Metadata-Flavor: Google' \
  http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email
# shows $GSA once the annotation is in place, even if step 3's binding is wrong
```

Step 5 returning 403 while step 6 prints `$GSA` means step 3's binding does not
match this namespace and Kubernetes service account: the member must be exactly
`serviceAccount:$PROJECT.svc.id.goog[$NAMESPACE/$KSA]`. Check it first with
`gcloud iam service-accounts get-iam-policy "$GSA" --project="$PROJECT"`.
Step 6 returning `<project-number>-compute@developer.gserviceaccount.com` means
step 1 did not take: the node pool is still on `GCE_METADATA` and the annotation
is being ignored. Node-pool updates recreate nodes, so run them in a maintenance
window.

The runner reads its identity once at startup, so step 4's rollout is not
optional — annotating the ServiceAccount alone leaves the running pods on the
old (or absent) identity.

### Networking

#### Private Cluster (Recommended for Production)
```hcl
is_private_cluster     = true
enable_cloud_nat       = true   # Required for private nodes when this module creates the VPC
master_ipv4_cidr_block = "172.16.0.0/28"
authorized_ip_ranges   = ["10.0.0.0/8"]
```

Network layout:
```
VPC
├── Subnet 0 (10.0.1.0/24) — GKE nodes
│   ├── Secondary range: pods-0 (10.1.0.0/16)
│   └── Secondary range: services-0 (10.10.0.0/20)
├── Subnet 1 (10.0.2.0/24)
│   ├── Secondary range: pods-1 (10.2.0.0/16)
│   └── Secondary range: services-1 (10.11.0.0/20)
└── Cloud NAT (static egress IP)
```

#### Public Cluster (Development Only)
```hcl
is_private_cluster = false
enable_cloud_nat   = false
```

#### Using an Existing VPC and Subnet

Set `existing_network` to deploy into an existing VPC/subnet instead of
creating new ones:

```hcl
existing_network = {
  network_id                     = "your-vpc"
  subnet_id                      = "your-subnet"
  pod_secondary_range_name       = "pods"
  services_secondary_range_name  = "services"
}
```

Short names resolve against `project_id`/`region`. If the VPC lives in a
different project (Shared VPC), use the full self-link instead, e.g.
`"projects/host-project/global/networks/your-vpc"`.

The subnet must already have pod/service secondary IP ranges (required for
VPC-native GKE clusters). Cloud NAT, if enabled, attaches to the existing VPC.
With an existing VPC and private nodes, either enable Cloud NAT here or make
sure the VPC already provides egress (for example its own Cloud NAT),
otherwise pods cannot reach the internet.

#### Upgrading: private nodes need Cloud NAT in a new VPC

`terraform plan` now fails when `is_private_cluster = true`,
`enable_cloud_nat = false` and `existing_network` is not set. Private nodes in
the VPC this module creates have no other route to the internet, so the runner
could not reach Matillion. To fix an affected configuration, set
`enable_cloud_nat = true` (this adds a Cloud Router, a static external address
and a Cloud NAT, see `modules/gcp/networking/main.tf`), or move to
`existing_network` with a VPC that provides its own egress. This root now
requires Terraform 1.2 or later.

### Pre-creating the node service account

GKE checks `iam.serviceAccounts.actAs` on the node service account when it
creates the cluster and the node pool. A service account created by this module
has no id before apply, so actAs cannot be limited to it in advance. Creating
the account once beforehand lets an IAM admin limit actAs to that one account.

One-time commands for an IAM admin:

```bash
gcloud iam service-accounts create runner-nodes \
  --project=<project-id> \
  --display-name="Matillion runner GKE nodes"

gcloud iam service-accounts add-iam-policy-binding \
  runner-nodes@<project-id>.iam.gserviceaccount.com \
  --project=<project-id> \
  --member="serviceAccount:<deployer-email>" \
  --role="roles/iam.serviceAccountUser"
```

Use `--member="user:<email>"` for a user deployer. To grant the role at project
level instead, add a condition on the account's unique id. Get the id with
`gcloud iam service-accounts describe runner-nodes@<project-id>.iam.gserviceaccount.com --format='value(uniqueId)'`
and use the condition expression
`resource.name == "projects/-/serviceAccounts/<unique-id>"`.

Then set in `terraform.tfvars`:

```hcl
existing_node_service_account_email = "runner-nodes@<project-id>.iam.gserviceaccount.com"
```

The module then creates no node service account, and both the cluster's
initial node pool and the runner node pool run as this account. The deployer
needs no `roles/iam.serviceAccountUser` at project level.

By default (`grant_node_project_roles = true`) Terraform grants this account
`roles/logging.logWriter`, `roles/monitoring.metricWriter` and
`roles/monitoring.viewer` on the project, and `terraform destroy` removes them,
including an identical grant made outside Terraform. Do not also grant these
three by hand.

With `grant_node_project_roles = false`, Terraform makes no project grant to
the node account and the deployer needs no project IAM rights for it. The IAM
admin grants the three roles instead:

```bash
gcloud projects add-iam-policy-binding <project-id> \
  --member="serviceAccount:runner-nodes@<project-id>.iam.gserviceaccount.com" \
  --role="roles/logging.logWriter"

gcloud projects add-iam-policy-binding <project-id> \
  --member="serviceAccount:runner-nodes@<project-id>.iam.gserviceaccount.com" \
  --role="roles/monitoring.metricWriter"

gcloud projects add-iam-policy-binding <project-id> \
  --member="serviceAccount:runner-nodes@<project-id>.iam.gserviceaccount.com" \
  --role="roles/monitoring.viewer"
```

```hcl
grant_node_project_roles = false
```

`grant_node_project_roles = false` without `existing_node_service_account_email`
fails at plan, because nobody would grant the three roles to the account the
module creates.

Grant any other role the nodes need (for example Artifact Registry read access
for private images) yourself.

#### Upgrading

With `existing_node_service_account_email` unset, an existing deployment plans
no change: the state entry moves from `google_service_account.gke_node_sa` to
`google_service_account.gke_node_sa[0]`, and the cluster's new `node_config`
is ignored.

Setting `existing_node_service_account_email` on an existing deployment plans:

- replacement of `google_container_node_pool.runner_nodes` (its
  `node_config.service_account` forces a new pool);
- replacement of the three `google_project_iam_member.gke_node_*` grants;
- destruction of the service account the module created.

The cluster itself is not replaced. The node pool is deleted before the new one
is created, so every runner pod stops and restarts on the new nodes. Plan for a
runner outage of several minutes (in europe-west1 a node pool create took 1m16s
and a destroy 3m34s). Deleting the old service account leaves a
`deleted:serviceAccount:...?uid=` member in the project IAM policy, which can
be removed with `gcloud projects remove-iam-policy-binding`.

With `grant_node_project_roles` unset, an existing deployment plans no change:
the three `google_project_iam_member.gke_node_*` grants move to `[0]`.

Setting `grant_node_project_roles = false` on an existing deployment destroys
the three node grants. Destroying a `google_project_iam_member` removes the
binding even when the admin made an identical one, so the admin grants the
three roles after that apply. Until then the nodes cannot write logs and
metrics.

### Pre-creating the runner service account

By default the module creates the runner service account and grants it
project-level roles, which needs `roles/iam.serviceAccountAdmin` and
`roles/resourcemanager.projectIamAdmin` at project level. An IAM admin can
create the account and make those grants once instead.

One-time commands for an IAM admin. The first grant uses the role from
[Pre-creating the runner secret creator role](#pre-creating-the-runner-secret-creator-role):

```bash
gcloud iam service-accounts create runner-workload \
  --project=<project-id> \
  --display-name="Matillion runner workload"

for role in \
  projects/<project-id>/roles/matillion_runner_secret_creator \
  roles/secretmanager.secretAccessor \
  roles/secretmanager.viewer \
  roles/browser; do
  gcloud projects add-iam-policy-binding <project-id> \
    --member="serviceAccount:runner-workload@<project-id>.iam.gserviceaccount.com" \
    --role="$role"
done

gcloud iam service-accounts add-iam-policy-binding \
  runner-workload@<project-id>.iam.gserviceaccount.com \
  --project=<project-id> \
  --member="serviceAccount:<deployer-email>" \
  --role="roles/iam.serviceAccountAdmin"
```

`roles/iam.serviceAccountAdmin` on this one account lets the deployer add the
Workload Identity members. A custom role holding only
`iam.serviceAccounts.getIamPolicy` and `iam.serviceAccounts.setIamPolicy` on
the account is enough.

Then set in `terraform.tfvars`:

```hcl
existing_runner_workload_service_account_email = "runner-workload@<project-id>.iam.gserviceaccount.com"
existing_runner_secret_creator_role_id         = "projects/<project-id>/roles/matillion_runner_secret_creator"
```

The module then creates no runner service account and makes no project-level
grant to it. It still grants the account access to the staging bucket, the
runner secret, `runner_gcs_buckets` and `additional_gcp_projects`. It adds the
two Kubernetes service accounts to `roles/iam.workloadIdentityUser` on the
account without removing members added there by others. The Helm value
`gcp.workloadIdentity.serviceAccountEmail` still comes from
`terraform output -raw runner_workload_sa_email`.

#### Upgrading

With `existing_runner_workload_service_account_email` and
`grant_node_project_roles` unset, an existing deployment plans no change. The
plan reports moves to `[0]` of `google_service_account.runner_workload_sa`,
`google_service_account_iam_binding.workload_identity_binding`, the four
runner project grants (`google_project_iam_member.runner_secret_creator`,
`runner_secret_accessor`, `runner_secret_viewer`, `runner_browser`) and the
three node grants (`google_project_iam_member.gke_node_*`).

Setting `existing_runner_workload_service_account_email` on an existing
deployment destroys the module's runner service account, its Workload Identity
binding and its four project grants, and replaces the staging bucket, runner
secret, extra bucket and additional project grants with the new member. Runner
pods lose GCP access until the admin's grants exist and the Helm release is
upgraded with the new email. Treat it as a migration with downtime.

## Outputs

After `terraform apply`, the following outputs are available:

| Output | Description |
|--------|-------------|
| `cluster_name` | GKE cluster name |
| `auth_config_command` | `gcloud` command to configure `kubectl` |
| `runner_workload_sa_email` | GCP SA email for Helm `gcp.workloadIdentity.serviceAccountEmail` |
| `gcs_bucket_name` | GCS bucket for runner staging storage |
| `secret_manager_secret_id` | Secret Manager secret ID |
| `nat_ip` | Static Cloud NAT egress IP (if `enable_cloud_nat = true`) |

## Monitoring and Observability

GKE integrates with Google Cloud Monitoring and Logging out of the box.

```bash
# View cluster logs in Cloud Logging
gcloud logging read "resource.type=k8s_container AND resource.labels.cluster_name=<cluster-name>" \
  --project=<project-id> --limit=50

# View metrics in Cloud Monitoring
gcloud monitoring dashboards list --project=<project-id>
```

### Prometheus Integration (Optional)

```bash
cd ../../helm/prometheus

helm install prometheus . \
  --create-namespace \
  --namespace monitoring

kubectl port-forward -n monitoring svc/prometheus-server 9090:80
```

## Security

### Shielded Nodes

Nodes are provisioned with Secure Boot and integrity monitoring enabled by default.

### Network Policies

Enable network policies in the Helm values:
```yaml
networkPolicy:
  enabled: true
  prometheusNamespace: monitoring
  allowHttp: true
```

### Secrets Management

OAuth credentials are stored as Kubernetes secrets. The GCP Secret Manager secret provisioned by Terraform can be used for additional application secrets.

```bash
# Store a secret value
gcloud secrets versions add <secret-id> --data-file=<file>

# Access from the runner workload SA (already has secretAccessor role)
```

## Operations

### Scaling

```bash
# Manual pod scaling
kubectl scale deployment matillion-runner-app --replicas=5 -n matillion

# View HPA status
kubectl get hpa -n matillion
kubectl describe hpa matillion-runner-hpa -n matillion
```

#### Sizing the HPA target (`averageValue`)

The HPA scales runner pods based on `hpa.metrics.target.averageValue` — the **target number of in-flight tasks per runner pod**, not a CPU/memory percentage.

- **Hard cap: 20.** Each runner instance runs a maximum of 20 concurrent tasks. Values above 20 mean the HPA can never reach the target — pods will saturate before the HPA reacts.
- **Recommended range: 15–17:**
  - `15` — **proactive** (spiky / latency-sensitive workloads, more headroom, higher cost)
  - `16` — **balanced** (recommended default — see `values-gcp.yaml`)
  - `17` — **reactive** (steady workloads, some queueing acceptable, lower cost)
- For dev/test GKE clusters, pick a much lower value (e.g. `5`) so small workloads trigger scale events.

#### Zone resilience

The cluster here is regional (`location = var.region`), so node pools already
span the zones of that region. That alone does not spread the *replicas* —
without a topology spread constraint the scheduler is free to stack them all in
one zone. Both chart settings are opt-in:

```yaml
topologySpread:
  enabled: true          # spread replicas across zones
podDisruptionBudget:
  enabled: true          # stop a node drain taking them all at once
```

They are only meaningful together: spreading across zones protects against a
zone outage, the budget protects against maintenance. See
`runner/helm/README.md` for the full option reference.

Health probes (`readinessProbe`, `livenessProbe`) are also available and default
to off — read the comments in `values.yaml` before enabling them, particularly
the relationship between the liveness failure window and the 12-hour termination
grace period.

### Application Updates

```bash
# Rolling update
helm upgrade matillion-runner . \
  --namespace matillion \
  --reuse-values \
  --set dpcAgent.dpcAgent.image.tag="v2.0.0"

# Monitor rollout
kubectl rollout status deployment/matillion-runner-app -n matillion
```

### Troubleshooting

```bash
# Check pod status and events
kubectl describe pod <pod-name> -n matillion

# View pod logs
kubectl logs <pod-name> -c matillion-runner-pods -n matillion

# Check Workload Identity is working: must print 200 (status only, never the token).
# 403 means the roles/iam.workloadIdentityUser binding does not list this
# namespace and service account (see "Binding an identity to a runner already installed").
kubectl exec <pod-name> -n matillion -- \
  curl -s -o /dev/null -w '%{http_code}\n' -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token"

# Informational: which Google service account the pod is configured with
kubectl exec <pod-name> -n matillion -- \
  curl -s -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email"
```

## Script runner sizing and scaling

How many sessions a pod holds, how many pods to run, and when to turn on the
HPA are the same on every cloud. They're in
[Sizing the script runner](../../helm/README.md#sizing-the-script-runner). This
section covers what is specific to GKE.

- **The node pool only grows by two per zone.** This module's node pool
  autoscales from `desired_node_count` to `desired_node_count + 2` in each zone
  of the region, and the `+ 2` isn't a variable. When the agent and script
  runner HPAs together need more than that, new pods stay Pending. Raise
  `desired_node_count` (which raises the billed floor in every zone), or run the
  script runner in its own node pool.
- **Autopilot** (a cluster you bring, not one this module creates) sets each
  pod's resources itself. It can lower the CPU limit to match the request,
  removing the burst headroom that lets many scripts start at once, and it
  bills on requests. If you run on Autopilot, size up rather than relying on
  the CPU limit.
- **Prometheus runs in `monitoring`** when installed as this README describes,
  which matches the runner chart's default `networkPolicy.prometheusNamespace`.

## Cleanup

```bash
# Uninstall Helm release
helm uninstall matillion-runner -n matillion
kubectl delete namespace matillion

# Empty the staging bucket (see below), then destroy infrastructure
gcloud storage rm "gs://$(terraform output -raw gcs_bucket_name)/**"
terraform destroy
```

### Empty the staging bucket first

This deployment creates a GCS staging bucket (`google_storage_bucket.staging` in `modules/gcp/gke`) with `force_destroy = false`. The runner's service account has `roles/storage.objectAdmin` on it, so it can write objects. If anything has been written to the bucket, `terraform destroy` fails on it with `Error trying to delete bucket <name> without force_destroy set to true`, leaving the bucket in state.

Run the Helm uninstall and namespace deletion first, so the runner stops writing to the bucket, as in the commands above. `terraform output -raw gcs_bucket_name` prints the bucket name, and `gcloud storage rm` deletes every object (the bucket is not versioned by this module). Empty the bucket before `terraform destroy`.

Objects in the bucket are not recoverable after `gcloud storage rm`. If a destroy has already failed on the bucket, empty it and run `terraform destroy` again.
