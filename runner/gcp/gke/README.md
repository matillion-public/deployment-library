# GCP GKE Deployment for Matillion Runner

This directory contains Terraform configurations for deploying the Matillion Maia Runner using Google Kubernetes Engine (GKE) — Google Cloud's managed Kubernetes service.

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
desired_node_count   = 2
machine_type         = "e2-standard-4"   # supports runnerSize=small or medium
is_private_cluster   = false
enable_cloud_nat     = false
authorized_ip_ranges = ["<your-office-ip>/32"]
```

#### Production Environment
```hcl
desired_node_count     = 3
machine_type           = "e2-standard-8" # supports runnerSize=large
is_private_cluster     = true
enable_cloud_nat       = true          # Required for private nodes
authorized_ip_ranges   = ["10.0.0.0/8", "203.0.113.0/24"]
master_ipv4_cidr_block = "172.16.0.0/28"
```

### Workload Identity

GKE Workload Identity allows pods to authenticate to GCP APIs without managing service account keys. The Terraform module:

1. Creates a GCP Service Account (`runner_workload_sa`)
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

# 5. Confirm the pod actually gets it — this is the only check that proves
#    all three layers line up.
kubectl exec -n "$NAMESPACE" deploy/matillion-runner-app -- \
  curl -sH 'Metadata-Flavor: Google' \
  http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email
# must print $GSA, not <project-number>-compute@developer.gserviceaccount.com
```

Step 5 returning the compute SA means step 1 did not take: the node pool is
still on `GCE_METADATA` and the annotation is being ignored. Node-pool updates
recreate nodes, so run them in a maintenance window.

The runner reads its identity once at startup, so step 4's rollout is not
optional — annotating the ServiceAccount alone leaves the running pods on the
old (or absent) identity.

### Networking

#### Private Cluster (Recommended for Production)
```hcl
is_private_cluster     = true
enable_cloud_nat       = true   # Required so private nodes can pull images
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

# Check Workload Identity is working
kubectl exec -it <pod-name> -n matillion -- \
  curl -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email"
```

## Cleanup

```bash
# Uninstall Helm release
helm uninstall matillion-runner -n matillion
kubectl delete namespace matillion

# Destroy infrastructure
terraform destroy
```
