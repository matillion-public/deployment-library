# Matillion Runner Helm Charts

This directory contains Helm charts for deploying the Matillion Maia Runner on Kubernetes with comprehensive monitoring capabilities.

## Charts

### `runner/` - Matillion Maia Runner
The main Helm chart that deploys the Matillion Runner with native Prometheus metrics support.

### `prometheus/` - Modular Prometheus Stack
Supporting chart for Prometheus metrics collection, custom metrics API, and Prometheus adapter with selective deployment capabilities. Supports integration with external Prometheus servers.

## Quick Start

### Prerequisites

#### Namespaces
Create the required namespaces before installation:

```bash
# Create namespace for Matillion Runner
kubectl create namespace matillion

# Create namespace for Prometheus monitoring
kubectl create namespace prometheus
```

#### Image Delivery & Network Requirements

The Helm chart's default image source depends on which values file you use:

| Values File | Registry | Notes |
|---|---|---|
| `values-aws.yaml` | `public.ecr.aws/matillion/etl-agent` | AWS ECR Public |
| `values-azure.yaml` | `matillion.azurecr.io/cloud-agent` | Matillion-operated public Azure Container Registry, anonymous pull |
| `values-gcp.yaml` | `europe-docker.pkg.dev/maia-492711/maia-runners/maia-runner` | Google Cloud Artifact Registry — Europe |
| | `us-docker.pkg.dev/maia-492711/maia-runners/maia-runner` | Google Cloud Artifact Registry — US |
| | `australia-southeast1-docker.pkg.dev/maia-492711/maia-runners/maia-runner` | Google Cloud Artifact Registry — Australia |

Both are public registries. Your cluster nodes (or workload identity) must have network access to whichever registry you target. For zero-egress environments, mirror the image into a customer-managed private registry and override `image.repository` (and `image.tag`) in your values file to point at the private mirror.

See [Network Requirements for Pulling the Runner Image](../../blogs/runner-image-pull-network-requirements.md) for supported network patterns and configuration steps.

### Install Runner Chart

> **Security Best Practice**: Always use values files instead of `--set` flags for sensitive data like secrets, API keys, and credentials. Command-line arguments may be visible in process lists and shell history.

#### Option 1: AWS EKS with IAM Roles (Recommended)
```bash
# Use the AWS template with environment variables
cp values-aws.yaml my-values.yaml
# Set your environment variables and customize the file
export MATILLION_RUNNER_CLIENT_ID="your-client-id"
export MATILLION_RUNNER_CLIENT_SECRET="your-client-secret"
export MATILLION_RUNNER_ROLE_ARN="arn:aws:iam::123456789012:role/your-role"
export MATILLION_RUNNER_ACCOUNT_ID="your-account-id"
export MATILLION_RUNNER_AGENT_ID="your-agent-id"

# Install with values file
envsubst < my-values.yaml | helm install matillion-runner ./runner \
  --namespace matillion \
  -f -
```

### Recommended Values File Approach

#### Step 1: Choose the Right Template
```bash
# For AWS EKS 
cp values-aws.yaml my-values.yaml

# For Azure AKS
cp values-azure.yaml my-values.yaml

# For Google Cloud GKE
cp values-gcp.yaml my-values.yaml
```

#### Step 2: Customize Your Values
```bash
# Edit your chosen values file
vim my-values.yaml

# For files with environment variables, set them first
export MATILLION_RUNNER_CLIENT_ID="your-client-id"
export MATILLION_RUNNER_CLIENT_SECRET="your-client-secret"
# ... other variables

# Validate the template before installation
helm template matillion-runner ./runner \
  --namespace matillion \
  -f my-values.yaml \
  --validate
```

> **Required — set the workload identity for your cloud.** The runner (and its
> script runner) authenticate to cloud services via the service account, so the
> identity below **must** be set before installing. The provider values files ship
> with a `<Placeholder>` here — leaving it unchanged causes authentication to fail
> (and, on EKS/AKS, can crash-loop the script runner when the projected token
> mount can't be created). Set the value for your cloud:
>
> **AWS EKS (IRSA)** — set the IAM role ARN in `values-aws.yaml`:
> ```yaml
> serviceAccount:
>   roleArn: "arn:aws:iam::<account-id>:role/<role-name>"
> ```
>
> **Azure AKS (Workload Identity)** — set the managed-identity client ID:
> ```yaml
> azure:
>   workloadIdentity:
>     clientId: "<workload-identity-client-id>"
> scriptRunner:
>   serviceAccount:
>     clientId: "<workload-identity-client-id>"   # if the script runner is enabled
> ```
>
> **Google GKE (Workload Identity)** — set the GCP service account to impersonate:
> ```yaml
> gcp:
>   workloadIdentity:
>     serviceAccountEmail: "<name>@<project>.iam.gserviceaccount.com"
> scriptRunner:
>   serviceAccount:
>     serviceAccountEmail: "<name>@<project>.iam.gserviceaccount.com"   # if the script runner is enabled
> ```
>
> **Alternatives (an identity other than per-workload)** — if your cluster can't
> use cloud-native workload identity, name the alternative explicitly. Turning
> workload identity off without naming one makes rendering **fail**, rather than
> installing a runner with no cloud identity at all:
> - **AWS** — set `aws.local.enabled: true` and provide `aws.local.region` /
>   `accessKeyId` / `secretAccessKey` (leave `serviceAccount.roleArn` unset).
> - **Azure** — set `azure.workloadIdentity.enabled: false` and either
>   `azure.servicePrincipal.enabled: true` with `clientId` / `clientSecret` /
>   `tenantId`, or `azure.nodeIdentity.enabled: true` to inherit the AKS node
>   pool's kubelet managed identity.
> - **GCP** — set `gcp.workloadIdentity.enabled: false` and
>   `gcp.nodeIdentity.enabled: true` to inherit the GKE node pool's service
>   account. There is no static-key equivalent, and this is not recommended —
>   see [Cloud identity is mandatory](#cloud-identity-is-mandatory).
> - **Local / dev** — start from `values-local.yaml`, which wires up static
>   credentials for all providers for out-of-cluster testing.

#### Placeholder Reference

The `values.yaml` template ships with `<Placeholder>` tokens that you **must**
replace before installing. Every token below must be set (unless marked optional):

| Placeholder | Where to get it | Applies to |
|---|---|---|
| `<CloudProvider>` | `aws`, `azure`, or `gcp` | all |
| `<AgentClientId>` | OAuth client ID from the Maia runner registration | all |
| `<AgentClientSecret>` | OAuth client secret from the Maia runner registration | all |
| `<MatillionAccountId>` | Maia account ID (Hub → account settings) | all |
| `<MatillionAgentId>` | Maia agent/runner ID from the runner registration | all |
| `<MatillionRegion>` | `us1` or `eu1` | all |
| `<ServiceAccountRoleArn>` | AWS IAM role ARN for IRSA (`arn:aws:iam::<account-id>:role/<role-name>`) | AWS |
| `<AgentImageRepository>` / `<AgentImageTag>` | Agent image location + tag (e.g. `public.ecr.aws/matillion/etl-agent` / `current`) | all |
| `<ScriptRunnerImageRepository>` | Script-runner image (e.g. `public.ecr.aws/matillion/maia-script-runner`) — only if `scriptRunner.enabled` | all |
| `<MaxReplicas>` / `<ScaleUpAverageValue>` | HPA bounds for your workload | all |
| `<AgentImageDigest>` / `<ScriptRunnerImageDigest>` | *Optional* — pin an immutable digest instead of a tag | all |
| `<KeyVaultName>` | *Optional* — only for Azure Key Vault secret hydration | Azure |
| `<GcpProjectId>` | *Optional* — only for GCP secret hydration | GCP |

Identity token — set exactly one per the "Required workload identity" note above:
`<ServiceAccountRoleArn>` (AWS), `azure.workloadIdentity.clientId` (Azure), or
`gcp.workloadIdentity.serviceAccountEmail` (GCP).

> **Tip:** find anything you missed before installing with
> `grep -nE '<[A-Za-z].*>' my-values.yaml` — it should return nothing.

#### Step 3: Install with Values File
```bash
# Install using your customized values file
helm install matillion-runner ./runner \
  --namespace matillion \
  -f my-values.yaml

# For files with environment variables
envsubst < my-values.yaml | helm install matillion-runner ./runner \
  --namespace matillion \
  -f -

# For multiple values files (e.g., base + overrides)
helm install matillion-runner ./runner \
  --namespace matillion \
  -f my-values.yaml \
  -f my-overrides.yaml
```

### Shared Multi-Tenant Platform

One cluster and one Prometheus can host many independently-scalable runners —
one Helm release per business unit, each in its own namespace with its own
identity, secrets and HPA. Onboarding another unit is a values file, not a chart
change.

```bash
helm install runner-grid ./runner -n bu-grid --create-namespace \
  -f runner/values-azure.yaml -f my-values-grid.yaml

helm install runner-retail ./runner -n bu-retail --create-namespace \
  -f runner/values-azure.yaml -f my-values-retail.yaml
```

Start from `runner/values-tenant-example.yaml`, which documents what must be
unique per tenant and what must never be changed.

Tenants do not interfere with each other's scaling: the adapter maps
`app_active_task_count` to both `pod` and `namespace`, and each runner's HPA is
`type: Pods`, so every Deployment scales on its own pods.

#### What must be unique per tenant

| Setting | Why |
|---------|-----|
| Helm release name and namespace | Every resource name and the pod `app` label derive from the release name |
| `config.oauthClientId` / `oauthClientSecret` | The runner's own credentials |
| `dpcAgent.dpcAgent.env.agentId` | Identifies the runner to the control plane |
| `serviceAccount.name` + cloud identity annotation | The identity is bound to `system:serviceaccount:<namespace>:<name>`. A tenant sharing another's service account inherits its secret access — this fails open, not closed |

#### What must never change

`app`, `app.kubernetes.io/name` and `app.kubernetes.io/instance` form the
Deployment's `spec.selector`, which Kubernetes treats as immutable. Changing one
makes `helm upgrade` of an existing release fail rather than roll. `commonLabels`
rejects these keys for that reason — use your own prefix for attribution:

```yaml
commonLabels:
  matillion.com/business-unit: grid
  matillion.com/cost-centre: "4471"
```

#### Wiring the shared Prometheus

Set once on the **prometheus** chart, not per tenant. Every tenant namespace has
to appear in both lists — one controls what service discovery finds, the other
what the Prometheus pod is permitted to reach, and a namespace missing from
either means that tenant's HPA sits at `minReplicas` with nothing in any log to
explain it:

```yaml
config:
  scrapeNamespaces: [bu-grid, bu-retail, bu-trading]
  # Each release labels its pods `<release>-matillion-runner-pods`, so one
  # literal name will not match more than a single tenant.
  scrapePodLabelRegex: ".*matillion-runner-pods"
networkPolicy:
  additionalScrapeNamespaces: [bu-grid, bu-retail, bu-trading]
```

See `prometheus/README.md` for how to verify every tenant is actually being
scraped after rollout.

### Install Prometheus Monitoring

#### Full Stack Deployment (Default)
```bash
# Install complete Prometheus stack (Prometheus server + adapter + custom metrics API)
helm install prometheus ./prometheus --namespace prometheus

# Verify all components are running
kubectl get pods -n prometheus
```

#### Selective Module Deployment
```bash
# Deploy only Prometheus adapter (connect to external Prometheus)
helm install prometheus ./prometheus --namespace prometheus \
  --set modules.prometheus.enabled=false \
  --set modules.adapter.enabled=true \
  --set modules.api.enabled=false \
  --set externalPrometheus.enabled=true \
  --set externalPrometheus.url="http://my-prometheus.monitoring.svc:9090"

# Deploy only custom metrics API
helm install prometheus ./prometheus --namespace prometheus \
  --set modules.prometheus.enabled=false \
  --set modules.adapter.enabled=true \
  --set modules.api.enabled=true \
  --set externalPrometheus.enabled=true \
  --set externalPrometheus.url="http://my-prometheus.monitoring.svc:9090"

# Deploy only Prometheus server
helm install prometheus ./prometheus --namespace prometheus \
  --set modules.prometheus.enabled=true \
  --set modules.adapter.enabled=false \
  --set modules.api.enabled=false
```

## Configuration

### Required Values

| Parameter | Description | Example |
|-----------|-------------|---------|
| `dpcAgent.dpcAgent.env.accountId` | Your Matillion account ID | `"12345"` |
| `dpcAgent.dpcAgent.env.agentId` | Matillion runner (Agent) identifier | `"runner-prod-01"` |
| `dpcAgent.dpcAgent.env.matillionRegion` | Matillion region | `"us1"` |
| `config.oauthClientId` | OAuth client ID | `"client-123"` |
| `config.oauthClientSecret` | OAuth client secret | `"secret-456"` |
| `serviceAccount.roleArn` | AWS IAM role ARN (required when `credentialSource` is `irsa`) | `"arn:aws:iam::..."` |
| `aws.region` | AWS region for the agent and script runner, on every credential source | `"eu-west-1"` |
| `aws.local.enabled` | Enable direct AWS credentials | `false` |
| `aws.local.region` | AWS Region (when local enabled) | `"us-west-2"` |
| `aws.local.accessKeyId` | AWS Access Key ID (when local enabled) | `"AKIA..."` |
| `aws.local.secretAccessKey` | AWS Secret Access Key (when local enabled) | `"secret..."` |
| `gcp.workloadIdentity.serviceAccountEmail` | GCP SA email (required for GKE) — `terraform output -raw runner_workload_sa_email` | `"runner@proj.iam.gserviceaccount.com"` |
| `azure.workloadIdentity.clientId` | Managed-identity client ID (required for AKS) | `"00000000-0000-..."` |
| `azure.subscriptionId` | Subscription for ARM lookups (Key Vault / storage listing). Pin it on multi-subscription tenants — `az account show --query id -o tsv` | `"00000000-0000-..."` |

Every cloud requires an identity. See [Cloud identity is mandatory](#cloud-identity-is-mandatory).

### AWS credential source

`serviceAccount.credentialSource` selects where the pods get their AWS
credentials. AWS only — Azure and GCP are selected by
`azure.workloadIdentity.enabled` / `gcp.workloadIdentity.enabled`.

| Value | What the chart renders | Use when |
|---|---|---|
| `irsa` *(default when unset)* | `eks.amazonaws.com/role-arn` annotation on the service account. Requires `serviceAccount.roleArn`. | Standard EKS with IRSA — what the Terraform in `runner/aws/eks` provisions. |
| `node` | No annotation and no injected credentials. The AWS SDK falls through its provider chain to IMDS and picks up the EC2 node instance profile. | The cluster's platform layer assigns AWS permissions per **node** rather than per service account — DuploCloud, and clusters predating IRSA. |
| `static` | `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` from a chart-managed secret, from `aws.local.*`. | Local development. Prefer `node` in any cluster whose nodes carry an instance profile. |

`aws.local.enabled: true` still means `static` and keeps working untouched.
Setting it alongside a `credentialSource` of anything other than `static` is
rejected at render time rather than resolved by precedence.

#### Region is separate from credentials

None of the three sources supplies a region. IRSA and the node profile deliver
credentials only, and the AWS SDKs treat region as an independent concern — so a
pod can hold entirely valid credentials and still fail at client construction
with `NoRegionError`. Set `aws.region` if anything relies on the environment for
it.

Script Pushdown is the usual case: the runner image forwards `AWS_REGION` and
`AWS_DEFAULT_REGION` into every SSH session through `~/.ssh/environment`, so a
pushed-down script that does not set a region itself has nothing to fall back
on. `aws.region` covers the agent and the script runner on every credential
source; `aws.local.region` is used as a fallback when set, so static callers do
not have to state it twice. Left empty, no region variables are rendered.

#### `node` has to be selected explicitly

Blanking `serviceAccount.roleArn` does **not** get you the node instance
profile. While the annotation is present the EKS pod identity webhook injects
`AWS_ROLE_ARN` and `AWS_WEB_IDENTITY_TOKEN_FILE` into the pod, and the
web-identity provider sits **ahead of IMDS** in the AWS credential chain. An
annotation naming a role the pod cannot assume therefore fails outright rather
than degrading to the node profile — the annotation has to be *absent*, not
merely unused. That is why this is an explicit switch and not an inference from
an empty `roleArn`.

With `credentialSource: node` the runner's AWS permissions are whatever the
nodes it lands on already hold, shared with every other pod on those nodes, and
invisible to this chart. Confirm the instance profile grants at least:

- `s3:ListAllMyBuckets` — account-wide by construction. The staging-bucket
  picker enumerates buckets and the API takes no resource constraint, so this
  cannot be scoped to one bucket. It returns bucket *names* only.
- `s3:ListBucket`, `s3:GetObject`, `s3:GetBucketLocation` on the buckets used
  for staging and for `EXTENSION_LIBRARY_LOCATION`.

`helm install` / `helm upgrade` prints a NOTES warning whenever the resolved
source is not `irsa`, and a second one if a now-inert `roleArn` is still set.

#### Binding to a service account the chart does not own

`serviceAccount.create: false` renders no ServiceAccount object and no
annotations; the pods bind to `serviceAccount.name` as it already exists. Use it
where the platform layer creates its own per-tenant accounts. The identity that
account carries is then managed entirely outside the release, and `helm upgrade`
cannot correct it. `scriptRunner.serviceAccount.create` / `.name` do the same for
the Script Pushdown runner.

```yaml
# DuploCloud-managed EKS: platform-owned SA, node instance profile.
serviceAccount:
  create: false
  name: duploservices-mytenant
  credentialSource: node
  roleArn: ""
```

### Optional Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `dpcAgent.replicas` | Number of runner replicas | `2` |
| `runnerSize` | T-shirt size driving requests/limits — `small` \| `medium` \| `large` \| `xlarge` | `small` |
| `runnerSizes` | Map of size → `{requests, limits}`. Override to add custom sizes. | see `values.yaml` |
| `dpcAgent.dpcAgent.resources` | Optional override; if non-empty, replaces the `runnerSize`-derived resources whole | `{}` |

#### Runner t-shirt sizes

`runnerSize` selects the resource block applied to the runner container. Each size maps to a `requests` / `limits` pair via the `runnerSizes` map in `values.yaml`:

| `runnerSize` | Requests (cpu / mem) | Limits (cpu / mem) | Suggested node SKU |
|---|---|---|---|
| `small` *(default)* | 1 / 4 GiB | 2 / 4 GiB | EKS `m5.large`, AKS `Standard_D2s_v5`, GKE `e2-standard-2` (or larger) |
| `medium` | 2 / 8 GiB | 4 / 8 GiB | EKS `m5.xlarge`, AKS `Standard_D4s_v5`, GKE `e2-standard-4` |
| `large` | 4 / 16 GiB | 8 / 16 GiB | EKS `m5.2xlarge`, AKS `Standard_D8s_v5`, GKE `e2-standard-8` |
| `xlarge` | 8 / 32 GiB | 16 / 32 GiB | EKS `m5.4xlarge`, AKS `Standard_D16s_v5`, GKE `e2-standard-16` |

Always size the node above the request to leave headroom for kubelet, system pods and the metrics sidecar. Pods will go `Pending` if no node satisfies the request — confirm node capacity (`kubectl describe nodes`) before scaling up.

To override a single size set entirely, populate `dpcAgent.dpcAgent.resources` (it replaces the size-derived block whole — set both `requests` and `limits`):

```yaml
runnerSize: small  # ignored when resources is non-empty
dpcAgent:
  dpcAgent:
    resources:
      requests: { cpu: "1500m", memory: "6Gi" }
      limits:   { cpu: "3",     memory: "6Gi" }
```

### Third-party Python libraries from an image you control

The documented way to add Python libraries to a runner is to stage them in
object storage and point `EXTENSION_LIBRARY_LOCATION` at the prefix; the
entrypoint copies them into `/usr/lib/pythonLibs` at startup. That prefix is an
interpreter-loaded code path, so write access to it is effectively code
execution in the runner — a supply-chain surface some security reviews will not
accept regardless of bucket policy and encryption at rest.

`extraVolumes` / `extraVolumeMounts` / `initContainers` are the alternative:
hydrate `/usr/lib/pythonLibs` from an image you build, sign and scan yourself,
with no object storage in the path. Both runner images already treat that
directory as runtime-populated and already have it on the interpreter's import
path — the agent via `SAAS_ETL_PYTHON_2_AND_3_PYTHONPATH`, the Script Pushdown
runner via a `.pth` file asserted at image build time — so this needs no
application-side change and no `sys.path` manipulation in your scripts.

Build an image whose only job is to carry the wheels:

```dockerfile
FROM python:3.12-slim AS build
# manylinux2014_x86_64 wheels only — the runner is linux/amd64 (Ubuntu 24.04,
# Python 3.12). Building on macOS or Windows pulls incompatible binaries.
RUN pip install --target=/libs --platform=manylinux2014_x86_64 \
      --only-binary=:all: opensearch-py

# Keep a shell in the final image: the init container below copies with `cp`.
# A `scratch` base carries the wheels in fewer bytes but then the copy has to be
# done by something else — the runner image's own tooling, or a busybox sidecar.
FROM python:3.12-slim
COPY --from=build /libs /libs
USER 65534
```

Then hydrate a shared `emptyDir` from it:

```yaml
initContainers:
  - name: python-libs
    image: registry.example.com/our-python-libs:1.4.0   # pin a tag, never :latest
    imagePullPolicy: Always
    command: ["sh", "-c", "cp -a /libs/. /hydrate/"]
    resources:
      requests: { cpu: "100m", memory: "128Mi" }
      limits:   { cpu: "500m", memory: "512Mi" }
    securityContext:
      allowPrivilegeEscalation: false
      runAsNonRoot: true
      readOnlyRootFilesystem: true
      capabilities:
        drop: ["ALL"]
    volumeMounts:
      - { name: python-libs, mountPath: /hydrate }

extraVolumes:
  - { name: python-libs, emptyDir: {} }

extraVolumeMounts:
  - { name: python-libs, mountPath: /usr/lib/pythonLibs }
```

`scriptRunner.initContainers`, `scriptRunner.extraVolumes` and
`scriptRunner.extraVolumeMounts` take the same three blocks for the Script
Pushdown runner. They are deliberately separate from the runner's — the two
workloads hydrate independently, and the Script Pushdown pod is usually where
you want the heavier library sets, since it does not delay the runner that
schedules pipelines.

Notes and constraints:

- **`runAsNonRoot: true` requires the image to declare a non-root user.** The
  `USER 65534` line above is what satisfies it; without a numeric `USER` in the
  image, the kubelet rejects the pod at admission rather than at build time.
- **The `resources` and `securityContext` blocks above are not decoration.**
  Without them the rendered pod fails `CKV_K8S_10`–`13` and `CKV_K8S_30` in
  checkov. As written, the init container adds zero findings over the same
  release without it.
- **A failing init container is a hard outage**, not a degraded runner — the pod
  will not start until it exits 0. Prefer `cp -a` over anything that can
  partially succeed.
- **Nothing validates the mount paths.** Mounting over `/tmp` or `/etc/config`
  will break the runner in ways the new mount gets blamed for.
- **`EXTENSION_LIBRARY_LOCATION` and this pattern both target the same
  directory.** Use one or the other; if both are set the entrypoint's download
  lands on top of the hydrated files.

## Shared Script Runner — Security Hardening (Customer-Hosted)

The opt-in Shared Script Runner (`scriptRunner.enabled: true`) executes
customer-authored Python and Bash scripts over SSH. In a Customer-Hosted Agent
(CHA) deployment **you own the cluster and its network**, so the items below are
hardening *you* should apply — the chart ships safe defaults but cannot enforce
network policy on a cluster with no CNI enforcer (Calico, Cilium, Azure NPM).

### Service-account token exposure

The runner pod sets `automountServiceAccountToken: true` **only** when Azure or
GCP Workload Identity is enabled (it needs the projected token for the OIDC
exchange). On AWS (IRSA) and on clusters without Workload Identity the token is
**not** mounted. Where it is mounted, a script running on the runner can read the
projected Kubernetes API token, so scope the runner's ServiceAccount to least
privilege: do **not** bind it to any `Role`/`ClusterRole` beyond what the cloud
identity exchange requires. The chart creates the SA with no `RoleBinding`; keep
it that way unless you have a specific need.

### Egress restriction and blocking cloud metadata (IMDS)

When `networkPolicy.enabled: true` the runner's egress is already default-deny
except DNS (53) and HTTPS (443). Cloud metadata endpoints (IMDS,
`169.254.169.254`, served over HTTP/80) are therefore unreachable from the
runner by default. **This only holds if your cluster runs a CNI that enforces
NetworkPolicy** — without one the policy is inert and a script can reach IMDS to
harvest node credentials.

To keep general HTTPS egress but explicitly carve out the link-local metadata
range (belt-and-braces, and useful if you widen egress), use the existing
`networkPolicy.additionalEgressRules` hook — it is applied to both the runner and
the script-runner NetworkPolicies:

```yaml
networkPolicy:
  enabled: true
  additionalEgressRules:
    # Allow HTTPS to anywhere EXCEPT the cloud metadata endpoint.
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
            except:
              - 169.254.169.254/32   # AWS/Azure/GCP IMDS
              - 169.254.0.0/16       # link-local (covers GKE metadata too)
      ports:
        - protocol: TCP
          port: 443
```

NetworkPolicy is allow-list only (there is no "deny" rule); the `ipBlock.except`
pattern above is how you exclude a destination from an otherwise-broad allow.

### Script output truncation (Python vs Bash)

Script output is truncated before it is returned to the Designer, and the two
interpreters behave differently — document this for pipeline authors so large
outputs aren't silently lost:

| Interpreter | Limit | Behaviour |
|---|---|---|
| Python | ~300 KB | Output is tail-truncated and an explicit `WARNING` is prepended to the returned output. |
| Bash | ~200 KB | Output is tail-truncated **silently** — no warning is emitted. |

If a script's result matters, write it to a durable sink (cloud storage, a table)
rather than relying on stdout. The canonical customer-facing reference is the
[Script Pushdown documentation](https://docs.matillion.com/data-productivity-cloud/);
this table is the deployment-side summary.

## Prometheus Chart Configuration

### Module Control Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `modules.prometheus.enabled` | Deploy Prometheus server | `true` |
| `modules.adapter.enabled` | Deploy Prometheus adapter | `true` |
| `modules.api.enabled` | Deploy custom metrics API | `true` |

### External Prometheus Integration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `externalPrometheus.enabled` | Use external Prometheus server | `false` |
| `externalPrometheus.url` | External Prometheus URL | `"http://prometheus.monitoring.svc.cluster.local:9090"` |
| `externalPrometheus.namespace` | External Prometheus namespace | `"monitoring"` |
| `externalPrometheus.serviceName` | External Prometheus service name | `"prometheus"` |

### Individual Component Control

| Parameter | Description | Default |
|-----------|-------------|---------|
| `adapter.enabled` | Enable adapter deployment (legacy) | `true` |
| `api.enabled` | Enable API deployment (legacy) | `true` |
| `prometheus.enabled` | Enable Prometheus deployment (legacy) | `true` |

### Horizontal Pod Autoscaler

| Parameter | Description | Default |
|-----------|-------------|---------|
| `hpa.maxReplicas` | Maximum replicas | `10` |
| `hpa.minReplicas` | Minimum replicas | `2` |
| `hpa.metrics.target.averageValue` | Target in-flight tasks per runner pod | `"16"` |
| `hpa.metricSource` | Metrics the HPA scales on: `legacy` (`app_*`) or `otel` (`matillion_agent_*`). `otel` needs prometheus chart 0.4.0+ | `legacy` |
| `metrics.legacy.enabled` | Expose the deprecated `/actuator/prometheus` endpoint to Prometheus | `true` |
| `metrics.otel.enabled` | Expose the OpenTelemetry `/metrics` endpoint (container port + NetworkPolicy ingress) | `true` |
| `metrics.otel.port` | OpenTelemetry exporter port; also passed to the runner as `OTEL_EXPORTER_PROMETHEUS_PORT` | `9464` |
| `metrics.annotationTarget` | Endpoint the `prometheus.io/*` pod annotations advertise (`legacy` or `otel`); they can name only one | `legacy` |

#### Sizing the HPA target (`averageValue`)

`hpa.metrics.target.averageValue` is the **target number of in-flight tasks per runner pod** that the HPA uses to decide when to scale. It is **not** a CPU/memory percentage.

- **Hard cap: 20.** Each runner instance can run a maximum of 20 concurrent tasks. Setting `averageValue` above 20 means the HPA can never reach the target — pods will saturate before the HPA reacts, so you'll see queueing rather than scaling.
- **Recommended range: 15–17**, depending on workload shape:
  - **`15` — proactive scaling.** Best for spiky or latency-sensitive workloads where you want headroom before pods saturate. Adds more pods, higher cost.
  - **`16` — balanced (default).** Good fit for most clients.
  - **`17` — reactive scaling.** Best for steady, predictable workloads where some queueing is acceptable. Fewer pods, lower cost.
- For **dev/test** clusters where you want to exercise the HPA on small workloads, pick a much lower value (e.g. `5`) so a handful of tasks triggers a scale-up event.

## Monitoring

### Prometheus Metrics

The runner serves two Prometheus endpoints while customers migrate
([migration guide](../../blogs/runner-metrics-migration.md)):

| Endpoint | Names | Status |
|---|---|---|
| `:9464/metrics` (`metrics.otel`) | `matillion_agent_*_unit`, plus JVM metrics | New standard. Needs a runner image built from DPC-55707 onwards |
| `:8080/actuator/prometheus` (`metrics.legacy`) | `app_*` | Deprecated; removed after cutover |

| Legacy | OpenTelemetry |
|---|---|
| `app_agent_status` (1=running, 2=pending shutdown, 3=shutting down, 0=other) | `matillion_agent_status_unit` |
| `app_agent_connected` | `matillion_agent_connected_unit` |
| `app_active_task_count` | `matillion_agent_task_running_unit` |
| `app_active_request_count` | `matillion_agent_request_active_unit` |
| `app_open_sessions_count` | `matillion_agent_open_sessions_unit` |
| `app_version_info` | `matillion_agent_version_unit` |

The HPA scales on the legacy pair by default. Set `hpa.metricSource: otel` to
scale on `matillion_agent_task_running` / `matillion_agent_request_active`
instead. That needs prometheus chart 0.4.0 or later, and an image that serves
`:9464`.

### Service Discovery

The `prometheus.io/*` annotations can name only one endpoint, so an
annotation-driven scraper sees only that one. They advertise the legacy endpoint
until cutover. Set `metrics.annotationTarget: otel` to move them:

```yaml
prometheus.io/scrape: "true"
prometheus.io/port: "8080"            # 9464 with annotationTarget: otel
prometheus.io/path: "/actuator/prometheus"  # /metrics with annotationTarget: otel
```

To scrape both, add an explicit job for port 9464. The bundled prometheus chart
does this as `matillion-runner-otel`.

## Advanced Configuration

### Custom Image Repositories

```yaml
dpcAgent:
  dpcAgent:
    image:
      repository: "your-registry/matillion-runner"
      tag: "v1.2.3"
```

### Resource Limits

Prefer `runnerSize` (see [Runner t-shirt sizes](#runner-t-shirt-sizes)) over hand-rolling resources:

```yaml
runnerSize: medium  # 2 vCPU / 8 GiB requests, 4 vCPU / 8 GiB limits
```

For arbitrary values, override the size map by setting `dpcAgent.dpcAgent.resources` directly:

```yaml
dpcAgent:
  dpcAgent:
    resources:
      limits:   { cpu: "4", memory: "8Gi" }
      requests: { cpu: "2", memory: "4Gi" }
```

### Cloud Provider Specific

#### Cloud identity is mandatory

The runner needs an identity in your cloud to reach Secret Manager / Key Vault /
Secrets Manager and object storage. The chart cannot create that identity — it
only annotates the Kubernetes ServiceAccount so the cloud can match it to one
you created. Get the annotation wrong or skip it and the install still succeeds;
the runner fails later, on its first call, which reads as a Matillion problem
rather than a deployment one.

So each provider has exactly one sanctioned way to opt out of per-workload
identity, and rendering **fails** if none is named:

| Provider | Default | The one alternative |
|---|---|---|
| AWS | `serviceAccount.roleArn` (IRSA) | `aws.local.enabled: true` — static access keys |
| Azure | `azure.workloadIdentity.clientId` | `azure.servicePrincipal.enabled: true`, or `azure.nodeIdentity.enabled: true` for the AKS kubelet identity |
| GCP | `gcp.workloadIdentity.serviceAccountEmail` | `gcp.nodeIdentity.enabled: true` — the GKE node pool's service account |

`nodeIdentity` on either cloud means the pod inherits the *node's* identity from
the instance metadata service: shared with every other pod on that node, and
scoped to whatever the node pool was granted. It is an escape hatch for
clusters that were built that way, not a recommendation.

The post-install NOTES print the commands to verify the binding actually took
effect — the annotation being present proves nothing on its own, because the
other half of the binding lives in IAM. For GKE specifically, including how to
bind an identity to a runner that is already installed, see
[`runner/gcp/gke/README.md`](../gcp/gke/README.md).

#### AWS EKS with IAM Roles
```yaml
cloudProvider: "aws"
serviceAccount:
  roleArn: "arn:aws:iam::123456789012:role/matillion-runner"
```

#### AWS Local/Minikube with Direct Credentials
```yaml
cloudProvider: "aws"
aws:
  local:
    enabled: true
    region: "us-west-2"
    accessKeyId: "AKIAEXAMPLE123"
    secretAccessKey: "your-secret-access-key"
# Note: serviceAccount.roleArn is not needed when using local credentials
```

#### Azure AKS with Workload Identity
```yaml
cloudProvider: "azure" 
serviceAccount:
  clientId: "your-workload-identity-client-id"
```

#### Azure AKS with Service Principal
```yaml
cloudProvider: "azure"
azure:
  servicePrincipal:
    enabled: true
    clientId: "your-service-principal-client-id"
    clientSecret: "your-service-principal-secret"
    tenantId: "your-azure-tenant-id"
```

#### GCP GKE with Workload Identity
```yaml
cloudProvider: "gcp"
gcp:
  workloadIdentity:
    enabled: true
    # terraform output -raw runner_workload_sa_email
    serviceAccountEmail: "matillion-runner@your-project.iam.gserviceaccount.com"
```

#### GCP GKE inheriting the node pool's service account
```yaml
cloudProvider: "gcp"
gcp:
  workloadIdentity:
    enabled: false
  nodeIdentity:
    enabled: true
```
Only for node pools running `--workload-metadata=GCE_METADATA`. The runner gets
whatever the node pool's service account has, which for the default compute SA
does not include the Secret Manager and GCS grants it needs. Prefer Workload
Identity; see `runner/gcp/gke/README.md`, "Identity is not optional".

## Testing

### Template Validation
```bash
# Test template rendering with values file
helm template test-release ./runner \
  --namespace matillion \
  -f test-values.yaml

# Validate against Kubernetes API
helm template test-release ./runner \
  --namespace matillion \
  -f test-values.yaml | \
  kubectl apply --dry-run=client -f -

# Use helm's built-in validation
helm install matillion-runner ./runner \
  --namespace matillion \
  -f test-values.yaml \
  --dry-run --validate
```

### Chart Testing
```bash
# Install chart-testing tool
helm plugin install https://github.com/helm/chart-testing

# Test charts
ct install --charts ./runner
```

## Upgrades

### Version Upgrades
```bash
# Upgrade chart to new version
helm upgrade matillion-runner ./runner \
  --namespace matillion \
  -f my-values.yaml

# Upgrade with new image version (update in values file)
# Edit my-values.yaml to change image.tag: "v2.1.1"
helm upgrade matillion-runner ./runner \
  --namespace matillion \
  -f my-values.yaml

# Check upgrade status
helm status matillion-runner
```

### Rollback
```bash
# Rollback to previous version
helm rollback matillion-runner 1
```

## Pre-Deployment Checks

The `checks/` directory contains validation scripts that detect environment issues **before** they cause hard-to-diagnose failures at runtime.

### Background

These scripts were created after a client experienced Python Script components failing with exit code 137. After extensive debugging, the root cause was identified as CrowdStrike Falcon's container drift detection killing Python processes when invoked with a file argument (`python3 <filepath>`). A pre-deployment check would have identified this immediately.

### When to Use

- **Before initial deployment** — validate the cluster and pod environment before going live
- **After cluster changes** — node pool upgrades, security tool rollouts, Kubernetes version upgrades
- **When troubleshooting** — Python script failures (especially exit 137), OOM kills, permission errors
- **During support escalations** — share the output with Matillion support for faster diagnosis

### Quick Start

```bash
# Auto-discover the runner pod and run all checks
./checks/run-check.sh

# Target a specific namespace
./checks/run-check.sh --namespace matillion

# Target a specific Helm release (when multiple exist)
./checks/run-check.sh --namespace matillion --release my-runner

# Use a specific pod directly
./checks/run-check.sh --pod my-runner-pod-abc123 --namespace matillion

# Custom kubeconfig
./checks/run-check.sh --kubeconfig /path/to/kubeconfig
```

### What It Checks

**Cluster-level** (run from your machine via kubectl):
- Security DaemonSets — CrowdStrike Falcon, Microsoft Defender, Falco, Sysdig, Twistlock/Prisma, Aqua, NeuVector
- Whether security agents are active on the same node as the runner pod
- Kubernetes version (flags end-of-life versions)
- Pod Security Standards on the runner namespace
- Runner pod status and restart count
- **Image & release track** — detects `current` vs `stable` track, reports registry (ECR/ACR), checks for image drift between spec and running digest
- **ServiceAccount & cloud identity** — validates AWS IRSA or Azure Workload Identity annotations
- **Secret availability** — verifies all referenced secrets exist with data keys
- **NetworkPolicy egress** — checks for DNS (port 53) and HTTPS (port 443) egress rules

**In-pod critical checks** (FAIL = blocks deployment):
- Python3 availability, inline execution, and file-based execution
- Inline vs file-based mismatch detection (the exact CrowdStrike drift pattern)
- `/tmp` writability and working directory access
- Java availability

**In-pod warnings** (non-blocking):
- `/dev/shm` size (>= 40MB), `/tmp` free space (>= 256MB)
- `restricteduser` user/group existence (informational — PRIVILEGED mode is expected default)
- `sudo` availability, `noexec` mount flags
- OOM kill history, memory and PID usage vs limits

**Environment info** (diagnostic data):
- Seccomp status, memory configuration, ulimits
- Environment variables (masked), Java/Python versions
- DNS resolution **and HTTPS connectivity** for Matillion platform endpoints (keycloak, OpenTelemetry)
- JVM heap settings, GC algorithm, and full JVM flags
- Disk space and mount flags

### Runner Release Tracks

The check script automatically detects which release track the runner is running:

| Track | Tag | Cadence | Best For |
|-------|-----|---------|----------|
| **Current** | `:current` | ~Twice/week (Tue & Thu) | Dev/test — latest features, early access |
| **Stable** | `:stable` | Monthly (1st of month) | Production — vetted, predictable upgrades |

- **Support window**: Only the latest release and the one immediately before it are supported for each track
- **Full SaaS runners** always run on the Current track
- You select the track when creating the runner and can change it via the [Update an Agent API](https://docs.maia.ai/api-reference/agents/update-an-agent)
- The image URI in your cloud deployment must match the track configured in Matillion

**Image URIs by cloud provider:**

| Cloud | Current | Stable |
|-------|---------|--------|
| AWS | `public.ecr.aws/matillion/etl-agent:current` | `public.ecr.aws/matillion/etl-agent:stable` |
| Azure | `matillion.azurecr.io/cloud-agent:current` | `matillion.azurecr.io/cloud-agent:stable` |

For more details see:
- [Runner updates](https://docs.matillion.com/data-productivity-cloud/agent/docs/agent-updates/)
- [Runner overview & migration](https://docs.matillion.com/data-productivity-cloud/agent/docs/agent-overview/#migrating-from-full-saas-to-hybrid-saas)

### Understanding the Output

The scripts produce color-coded output with a remediation summary:

- **[PASS]** — check passed, no action needed
- **[WARN]** — potential issue, review recommended
- **[FAIL]** — critical issue, must be resolved before deployment
- **[INFO]** — diagnostic data for reference

Any FAIL or WARN results include numbered remediation steps at the end with specific fix instructions.

**Exit code**: `0` = all critical checks passed, `1` = one or more critical failures.

### Running the In-Pod Script Standalone

If you already have a shell in the pod, you can run the validation script directly:

```bash
# Copy and run manually
kubectl cp checks/pre-deployment-check.sh <namespace>/<pod>:/tmp/check.sh
kubectl exec -n <namespace> <pod> -- bash /tmp/check.sh
```

## Troubleshooting

### Common Issues

**Runner pod not starting:**
```bash
# Check pod status
kubectl get pods -n matillion -l app=matillion-runner

# Check pod logs
kubectl logs -n matillion -l app=matillion-runner

# Check events
kubectl describe pod -n matillion -l app=matillion-runner
```

**Metrics not being scraped:**
```bash
# Test both metrics endpoints directly from the runner container
kubectl port-forward -n matillion deployment/matillion-runner 8080:8080 9464:9464
curl http://localhost:8080/actuator/prometheus   # legacy, app_*
curl http://localhost:9464/metrics               # OpenTelemetry, matillion_agent_*

# Check Prometheus is discovering targets
kubectl port-forward -n prometheus svc/prometheus 9090:9090
# Navigate to http://localhost:9090/targets
```

### Debug Mode

Enable debug logging:
```yaml
dpcAgent:
  dpcAgent:
    env:
      LOG_LEVEL: "DEBUG"
```

## Examples

### Production EKS Configuration
```yaml
# production-values.yaml
cloudProvider: "aws"
config:
  oauthClientId: "your-client-id"
  oauthClientSecret: "your-client-secret"  # Consider using external secrets
serviceAccount:
  roleArn: "arn:aws:iam::123456789012:role/matillion-runner-prod"
dpcAgent:
  replicas: 3
  dpcAgent:
    env:
      accountId: "12345"
      agentId: "prod-runner-01"
      matillionRegion: "us1"
    image:
      repository: "your-registry/matillion-runner"
      tag: "v2.1.0"
      imagePullPolicy: "IfNotPresent"
    resources:
      limits:
        cpu: "2"
        memory: 4Gi
      requests:
        cpu: "1"
        memory: 2Gi
hpa:
  maxReplicas: 20
  minReplicas: 3
  metrics:
    target:
      averageValue: "16"  # Target in-flight tasks per pod (cap: 20)
networkPolicy:
  enabled: true
  additionalEgressRules:
    - to:
      - namespaceSelector:
          matchLabels:
            name: prometheus
      ports:
      - protocol: TCP
        port: 9090
```

### Development Configuration
```yaml
# dev-values.yaml
dpcAgent:
  replicas: 1
  dpcAgent:
    resources:
      limits:
        cpu: "1"
        memory: 2Gi
hpa:
  maxReplicas: 3
  minReplicas: 1
```

### Local/Minikube Configuration
```yaml
# minikube-values.yaml (based on values.yaml template)
cloudProvider: "aws"
config:
  oauthClientId: "dev-client-id"
  oauthClientSecret: "dev-client-secret"
aws:
  local:
    enabled: true
    region: "us-west-2"
    accessKeyId: "AKIAEXAMPLE123"  # Use environment variables in practice
    secretAccessKey: "your-secret-key"  # Use environment variables in practice
dpcAgent:
  replicas: 1
  dpcAgent:
    env:
      accountId: "54321"
      agentId: "minikube-dev-runner"
      matillionRegion: "us1"
    image:
      repository: "matillion-runner"
      tag: "latest"
      imagePullPolicy: "Always"
    resources:
      limits:
        cpu: "500m"
        memory: 1Gi
      requests:
        cpu: "250m"
        memory: 512Mi
hpa:
  maxReplicas: 2
  minReplicas: 1
  metrics:
    target:
      averageValue: "5"  # Low target so test workloads trigger scale events
networkPolicy:
  enabled: false  # Simplified for local development
```

### Prometheus Modular Deployment Examples

#### External Prometheus Integration
```yaml
# external-prometheus-values.yaml
# Deploy only adapter and API to connect to existing Prometheus
modules:
  prometheus:
    enabled: false
  adapter:
    enabled: true
  api:
    enabled: true

externalPrometheus:
  enabled: true
  url: "http://prometheus.monitoring.svc.cluster.local:9090"
  namespace: "monitoring"
  serviceName: "prometheus"

# Install command:
# helm install prometheus ./prometheus --namespace prometheus -f external-prometheus-values.yaml
```

#### Standalone Prometheus Server
```yaml
# prometheus-only-values.yaml  
# Deploy only Prometheus server without adapter/API
modules:
  prometheus:
    enabled: true
  adapter:
    enabled: false
  api:
    enabled: false

prometheus:
  prometheus:
    resources:
      limits:
        cpu: "4"
        memory: 8Gi
      requests:
        cpu: "1"
        memory: 2Gi

# Install command:
# helm install prometheus ./prometheus --namespace prometheus -f prometheus-only-values.yaml
```

#### Custom Metrics Only
```yaml
# custom-metrics-values.yaml
# Deploy only custom metrics components (adapter + API)
modules:
  prometheus:
    enabled: false
  adapter:
    enabled: true
  api:
    enabled: true

externalPrometheus:
  enabled: true
  url: "http://my-prometheus.production.svc:9090"

# Install command:
# helm install prometheus ./prometheus --namespace prometheus -f custom-metrics-values.yaml
```

### Secrets Management Example
```yaml
# secrets-values.yaml (keep this file secure and out of version control)
config:
  oauthClientId: "actual-client-id"
  oauthClientSecret: "actual-client-secret"
aws:
  local:
    accessKeyId: "AKIAACTUALKEY123"
    secretAccessKey: "actual-secret-access-key"
```

```bash
# .gitignore
secrets-values.yaml
*-secrets.yaml
my-*-values.yaml
```

## Local Development with Minikube

### Setup Minikube
```bash
# Start minikube
minikube start --cpus=4 --memory=8g

# Enable ingress addon
minikube addons enable ingress
```

### Deploy to Minikube
```bash
# Create namespaces
kubectl create namespace matillion
kubectl create namespace prometheus

# Deploy Prometheus first
helm install prometheus ./prometheus --namespace prometheus

# Deploy runner with values file (recommended)
cp values.yaml minikube-values.yaml
# Edit minikube-values.yaml to enable aws.local and add your credentials

helm install matillion-runner ./runner \
  --namespace matillion \
  -f minikube-values.yaml


# Check deployment status
kubectl get pods -n matillion
kubectl get pods -n prometheus
```