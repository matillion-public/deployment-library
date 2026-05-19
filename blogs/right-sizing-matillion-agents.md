# Right-sizing Matillion Agents: T-Shirt Sizing Across Orchestrators

Picking CPU and memory for a Matillion agent used to mean re-reading three different orchestrator pages every time you stood up a cluster. Fargate has a fixed table of valid `cpu`/`memory` combinations. Azure Container Apps enforces a 1:2 vCPU-to-memory ratio on the Consumption profile and refuses anything else. Kubernetes lets you ask for whatever you want — but if no node has the headroom, your pod sits in `Pending` forever and nothing tells you that's the problem.

So this repo now exposes a single `agent_size` (Terraform) / `agentSize` (Helm) variable with four t-shirt sizes. You pick a size, the templates translate it into whatever the underlying orchestrator actually accepts. The defaults match the previous fixed values — `small` is identical to what was deployed before this change — so existing tfvars files keep working and existing helm releases keep their resource block.

This post covers what the sizes are, why they're set the way they are, and what to watch out for on each cloud.

## The four sizes

| Size | vCPU | Memory | Typical workload |
|---|---|---|---|
| `small` *(default)* | 1 | 4 GiB | Light/dev workloads; single-pipeline tenants; the previous fixed default |
| `medium` | 2 | 8 GiB | Most production deployments; moderate concurrent pipelines |
| `large` | 4 | 16 GiB | Heavy ELT, large staged datasets, Snowflake/BigQuery transformation-heavy work |
| `xlarge` | 8 | 32 GiB | Big concurrent fan-outs; Python/JDBC drivers loaded with custom libraries; Linux-only on ECS Fargate |

Pick the smallest size that comfortably holds your peak working set. If you don't know your peak yet, start at `medium` for production, `small` for dev — and revisit once you have a few weeks of metrics.

## Where it goes

| Where you set it | Variable | Default |
|---|---|---|
| ECS Fargate Terraform — `agent/aws/ecs/terraform.tfvars` | `agent_size` | `small` |
| Azure Container Apps Terraform — `agent/azure/container_apps/terraform.tfvars` | `agent_size` | `small` |
| Helm chart (EKS/AKS/GKE/local) — `values.yaml` or `--set` | `agentSize` | `small` |

The chart's per-cloud values files (`values-aws.yaml`, `values-azure.yaml`, `values-gcp.yaml`) all default to `small` and explicitly empty `dpcAgent.dpcAgent.resources` so the size map drives the deployment. To bypass the map for one specific install, set `dpcAgent.dpcAgent.resources` directly — that block, when non-empty, replaces the size-derived requests/limits whole.

## Per-orchestrator notes

### AWS ECS Fargate

Fargate restricts task `cpu` and `memory` to a fixed matrix of pairs. Every t-shirt size lands on a valid combination:

| Size | `agent_cpu` | `agent_memory` |
|---|---|---|
| `small` | 1024 | 4096 |
| `medium` | 2048 | 8192 |
| `large` | 4096 | 16384 |
| `xlarge` | 8192 | 32768 |

`xlarge` (8 vCPU / 32 GiB) is **Linux-only** on Fargate. Windows tasks cap at 4 vCPU / 30 GiB.

Need a different combination — say, 4 vCPU / 30 GiB? Set `agent_cpu` and `agent_memory` directly in `terraform.tfvars`. Both must be set together and the pair must be a valid Fargate combination, otherwise the task definition is rejected at apply time.

### Azure Container Apps

This is where the t-shirt sizes earn their keep. Container Apps offers two compute modes:

- **Consumption profile** — pay-per-use, but enforces a 1:2 vCPU:Gi ratio (1 vCPU = 2 Gi, 2 vCPU = 4 Gi …). Maxes out at 4 vCPU / 8 Gi.
- **Dedicated workload profiles** — D-series and E-series VMs, no ratio enforcement, but you pay for the whole profile.

The t-shirt sizes (1c/4Gi, 2c/8Gi, …) all violate the 1:2 ratio, so they can't run on Consumption. The template runs them on Dedicated workload profiles instead, and the size also drives `workload_profile_type`:

| Size | vCPU / Memory | `workload_profile_type` |
|---|---|---|
| `small` | 1 / 4 GiB | `D4` |
| `medium` | 2 / 8 GiB | `D4` |
| `large` | 4 / 16 GiB | `D4` (consumes the whole profile per replica) |
| `xlarge` | 8 / 32 GiB | `D8` (consumes the whole profile per replica) |

If you want memory-optimised E-series (4:1 memory:cpu) or a different profile entirely, set `workload_profile_type`, `container_cpu` and `container_memory` directly — they each take precedence over the size map.

> **Heads up:** Container Apps replicas are billed per workload-profile vCPU. `large` and `xlarge` aren't four/eight times the price of `small` — they're whole-profile reservations. Look at the per-vCPU pricing for D4/D8 in your region before scaling up `replica_count`.

### Kubernetes (EKS / AKS / GKE)

Kubernetes is the easy case for resources but the awkward case for nodes. The chart sets pod requests/limits from the size map, but the cluster's node SKU has to be big enough to schedule them — *and* leave room for kubelet, system pods, and a metrics sidecar if you have one.

| `agentSize` | Pod requests | Recommended node (EKS / AKS / GKE) |
|---|---|---|
| `small` | 1 vCPU / 4 GiB | `m5.large` / `Standard_D2s_v5` / `e2-standard-2` |
| `medium` | 2 vCPU / 8 GiB | `m5.xlarge` / `Standard_D4s_v5` / `e2-standard-4` |
| `large` | 4 vCPU / 16 GiB | `m5.2xlarge` / `Standard_D8s_v5` / `e2-standard-8` |
| `xlarge` | 8 vCPU / 32 GiB | `m5.4xlarge` / `Standard_D16s_v5` / `e2-standard-16` |

Always pick a node tier above the request. `medium` (2c/8Gi requests) on a 2-vCPU node leaves nothing for the kubelet — the pod will end up `Pending`, or worse, evicted under load. Confirm with `kubectl describe nodes` before you scale up.

EKS Fargate (the EKS template uses Fargate by default, not managed nodes) inherits the same task-level cpu/memory rules as ECS Fargate — the same combinations apply.

## When to override

The size map handles 95% of deployments. Reach for the override fields when:

- **You need a non-standard Fargate combination** — e.g. 2 vCPU / 16 GiB. Set `agent_cpu = 2048` and `agent_memory = 16384` directly.
- **Container Apps E-series or memory-heavy workloads** — set `workload_profile_type = "E4"`, `container_cpu = "1.0"`, `container_memory = "8Gi"`.
- **Kubernetes burstable patterns** — set `dpcAgent.dpcAgent.resources` with millicore CPU requests for tighter packing (e.g. requests 1500m, limits 3).
- **You're isolating a noisy neighbour** — bump `cpu` requests close to `cpu` limits to reduce CPU throttling under contention.

The Terraform overrides take precedence over the size map (set both `agent_cpu` and `agent_memory` together). The Helm override (`dpcAgent.dpcAgent.resources`) replaces the size-derived block whole when non-empty — set both `requests` and `limits`, not just one.

## Picking the right size from telemetry

If you're already running an agent and want to right-size it:

1. Pull the last two weeks of CPU/memory utilisation from CloudWatch (ECS), Azure Monitor / Log Analytics (ACA, AKS), or `metrics-server` (EKS, GKE).
2. Look at the **p95** of memory used — not the mean. Memory is the harder constraint; an agent that mean-uses 3 GiB but p95-uses 5 GiB will OOM on `small`.
3. Look at **CPU throttling time** (`container_cpu_cfs_throttled_seconds_total` for Kubernetes; CloudWatch `CPUUtilization` for ECS). If you're seeing >5% throttling at peak, bump up a size.
4. If memory is fine and CPU is hot, you can push CPU limits up via the override path without changing memory — though for the t-shirt sizes the simpler answer is usually to step up.

A rough heuristic: if your p95 memory is below 60% of the size's memory and CPU throttling is below 1%, drop a size. If p95 memory is above 80% or CPU throttling is above 5%, go up a size.

## Migrating an existing deployment

If you're upgrading from a pre-`agent_size` checkout:

- **ECS / Container Apps Terraform** — your existing `agent_cpu` / `agent_memory` / `container_cpu` / `container_memory` settings still work as overrides. To switch to the t-shirt model, comment those out and set `agent_size` instead.
- **Helm chart** — old `dpcAgent.dpcAgent.resources` blocks still win as overrides. To switch to the t-shirt model, replace that block with `resources: {}` and set `agentSize`.
- **Defaults** — `agent_size = "small"` produces 1 vCPU / 4 GiB on every orchestrator, which matches the previous fixed default. Existing deployments that don't set `agent_size` get the same shape they had before.

## Summary

One variable, four sizes, every orchestrator. Pick `small` until your telemetry says otherwise, and check the per-orchestrator notes above before you scale up — Container Apps' workload profiles and Kubernetes' node-size rules are the two places where the wrong choice silently fails.

## See also

- [Helm chart README](../agent/helm/README.md) — full `agentSize` / `agentSizes` reference
- [AWS ECS template README](../agent/aws/ecs/README.md) — ECS-specific sizing notes
- [Azure Container Apps template README](../agent/azure/container_apps/README.md) — Container Apps workload-profile mapping
- [Autoscaling Matillion Agents](./autoscaling-matillion-agents.md) — pairs well with sizing: pick the right per-pod size first, then scale replicas on workload metrics
