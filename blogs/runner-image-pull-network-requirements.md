# Network Requirements for Pulling the Runner Image

This guide explains how the Matillion Runner image is delivered, what network access your environment needs to retrieve it, and the options available when egress is restricted. It also covers the third-party Prometheus images bundled with the Helm-based deployment paths.

## Where the image lives

| Deployment path | Default image source | Registry type |
|---|---|---|
| AWS ECS, AWS EKS (Helm `values-aws.yaml`) | `public.ecr.aws/matillion/etl-agent` | AWS ECR Public |
| Azure AKS, Azure Container Apps (Helm `values-azure.yaml`) | `matillion.azurecr.io/cloud-agent` | Matillion-operated public Azure Container Registry (anonymous pull) |

Both registries are public. Both are pulled over the internet by default. Both are also subject to the egress posture of the environment you deploy into.

Image tag cadence:
- `current` — updated 2+ times per week
- `stable` — updated approximately monthly

## Decision tree — pick your egress posture

Use this to choose the configuration path that matches your environment:

| Egress posture | Recommended path |
|---|---|
| **Open egress** — your workload can reach `0.0.0.0/0` on TCP 443 | No special configuration. The default templates pull successfully. |
| **Whitelisted egress** — outbound is permitted but only to allowed FQDNs/IPs | Extend your allowlist to include the registry endpoints for your cloud (see [AWS](#aws-allowlist) / [Azure](#azure-allowlist) sections). |
| **Zero or restricted egress** — your workload cannot reach the public internet | Mirror the Runner image into a private registry you operate in your deployment region and override the deployment's image reference. See [AWS private mirror](#aws-private-mirror-pattern) / [Azure private mirror](#azure-private-mirror-pattern). |

The rest of this guide expands each path with cloud-specific detail.

---

## Background — Why restricted egress fails

### AWS path: `public.ecr.aws`

ECR Public is best understood as a thin shim over Amazon S3 with a CloudFront distribution in front of layer data. The control plane — the API that authenticates pulls and resolves image manifests — is operated by AWS only in `us-east-1` and `us-west-2`.

Source: [Amazon ECR Public endpoints and quotas — AWS General Reference](https://docs.aws.amazon.com/general/latest/gr/ecr-public.html).

When a workload pulls from `public.ecr.aws`, three network calls happen:

1. **Auth + manifest resolution** to `ecr-public.us-east-1.amazonaws.com` (or `api.ecr-public.us-east-1.amazonaws.com`) — always routes to `us-east-1`, regardless of which region the workload runs in
2. **Layer data delivery** via Amazon CloudFront edge nodes (global)
3. **Layer blob downloads** from the regional S3 bucket `prod-<region>-starport-layer-bucket` (source: [Amazon ECR interface VPC endpoints](https://docs.aws.amazon.com/AmazonECR/latest/userguide/vpc-endpoints.html))

In a workload deployed outside `us-east-1` / `us-west-2` with no permitted egress, step 1 fails first.

#### Why a VPC endpoint won't fix this directly

AWS only offers an ECR Public PrivateLink endpoint in `us-east-1` (per the [ECR VPC endpoints documentation](https://docs.aws.amazon.com/AmazonECR/latest/userguide/vpc-endpoints.html): *"VPC endpoints support Amazon ECR Public repositories through the AWS API SDK endpoint in US East (N. Virginia)."*). You cannot create a VPC endpoint for ECR Public in `eu-west-1`, `ap-southeast-2`, or any other region — the service endpoint does not exist there. VPC endpoints become useful only after the image has been moved into your own private ECR registry.

#### AWS regions that don't require special handling

| Region | ECR Public access |
|---|---|
| `us-east-1` (N. Virginia) | Native — no special handling required |
| `us-west-2` (Oregon) | Native — no special handling required |
| All other AWS regions | ECR Public API calls must reach `us-east-1` over the internet |

### Azure path: `matillion.azurecr.io`

`matillion.azurecr.io` is a Matillion-operated public Azure Container Registry with **anonymous pull** enabled — no credentials or workload identity are required to pull. It is **not** a customer-hosted registry; the `matillion.azurecr.io/cloud-agent` reference in the Helm chart is a public image source you can pull directly, the same way `public.ecr.aws/matillion/etl-agent` works on AWS.

Unlike AWS ECR Public — which has a centralised control plane in `us-east-1` that all regional pulls must reach — every Azure Container Registry is **regional**. `matillion.azurecr.io` lives in a single Azure region of Matillion's choosing, with no fixed cross-region control plane that all pulls must route through. If your workload runs in a region other than the registry's home region you still reach it (over the internet, or over Microsoft's backbone if egress is configured via service tags), but there is no equivalent of the ECR Public regional-anchoring problem.

When a workload pulls from `matillion.azurecr.io`, two ACR endpoints are involved (per Microsoft's [ACR firewall access rules documentation](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-firewall-access-rules)):

1. **Registry endpoint** — `matillion.azurecr.io` — authentication (anonymous in this case) and image manifest resolution
2. **Regional data endpoint** — `matillion.<region>.data.azurecr.io` — image layer blob downloads, where `<region>` is the Azure region the ACR is hosted in

Both endpoints must be reachable on TCP 443 for a successful pull. A workload with no permitted egress to either cannot pull the image and must use the [private mirror pattern](#azure-private-mirror-pattern) below.

---

## AWS — Symptoms of an image pull failure (ECS Fargate)

If you're investigating a suspected image-pull problem in an AWS deployment, the following are the typical signals:

- Service events report `CannotPullContainerError` with messages such as `... pull access denied` or `... i/o timeout`
- Tasks cycle through `PROVISIONING` → `STOPPED` without reaching `RUNNING`
- `aws ecs describe-tasks` shows `stoppedReason: "Task failed to start"` with the underlying pull error in the container's `reason` field
- CloudWatch Container Insights / task logs show no application output (the container never started)

If these match what you're seeing, work through the configuration paths below.

---

## AWS — Private Mirror Pattern (Recommended) {#aws-private-mirror-pattern}

For AWS deployments — and especially if you are in a regulated or restricted-network environment — the recommended approach is to mirror the Runner image into your own private ECR registry in your deployment region. Your workloads then pull privately via VPC endpoints with no internet egress required, and the pattern aligns with how most enterprise teams already manage container images.

This is preferred over the egress/whitelisting approach below because it gives you full control over the registry path, simpler operational reasoning, and a clean fit with the AWS PrivateLink semantics your security team will already be familiar with.

### Steps

1. **Pull the public image** in a staging environment with internet access — a DMZ host, build server, or CI/CD pipeline:
   ```
   docker pull public.ecr.aws/matillion/etl-agent:current
   ```
2. **Tag and push** to a private ECR repository in your deployment region:
   ```
   docker tag public.ecr.aws/matillion/etl-agent:current \
     <account>.dkr.ecr.<region>.amazonaws.com/matillion/etl-agent:current
   docker push <account>.dkr.ecr.<region>.amazonaws.com/matillion/etl-agent:current
   ```
3. **Override the deployment's image reference** to point at your private ECR URI:
   - Terraform (ECS): set `image_url = "<account>.dkr.ecr.<region>.amazonaws.com/matillion/etl-agent:current"`
   - Helm (EKS): set `image.repository` to your private ECR path and `image.tag` to your tag
4. **Provision VPC endpoints** so the workload can pull privately (see table below)
5. **Establish a refresh process** to re-mirror the image against Matillion's release cadence (`current` 2+/week, `stable` ~monthly)

### Required VPC endpoints

Per the [Amazon ECR interface VPC endpoints documentation](https://docs.aws.amazon.com/AmazonECR/latest/userguide/vpc-endpoints.html):

| Endpoint | Type | Purpose |
|---|---|---|
| `com.amazonaws.<region>.ecr.dkr` | Interface | Docker Registry API (image pull) |
| `com.amazonaws.<region>.ecr.api` | Interface | ECR API — required for ECS Fargate platform 1.4.0+ |
| `com.amazonaws.<region>.s3` | Gateway | Image layer blob downloads (no per-hour cost) |
| `com.amazonaws.<region>.logs` | Interface | CloudWatch Logs (only when no internet egress) |
| `com.amazonaws.<region>.secretsmanager` | Interface | Secrets Manager (only when no internet egress) |

Enable Private DNS on the interface endpoints so the standard ECR FQDNs resolve to the VPC endpoint IPs.

### AWS alternative: ECR Pull-Through Cache

AWS ECR supports a [pull-through cache rule](https://docs.aws.amazon.com/AmazonECR/latest/userguide/pull-through-cache.html) that automatically mirrors images from `public.ecr.aws` into your private ECR on demand. This works, but note: per AWS's documentation, *"When an image is pulled using a pull through cache rule for the first time, if you've configured Amazon ECR to use an interface VPC endpoint using AWS PrivateLink then you need to create a public subnet in the same VPC, with a NAT gateway, and then route all outbound traffic to the internet from their private subnet to the NAT gateway in order for the pull to work."* In other words, the first pull of every new tag still requires internet-reachable egress; subsequent pulls do not.

In most environments the manual private-mirror pattern is more transparent operationally; pull-through cache is a reasonable fit when you do not have an existing private-image ingestion process and you can accommodate the first-pull internet requirement.

---

## AWS — Whitelisted Egress (Alternative) {#aws-allowlist}

If your environment uses an internet-reachable egress path with FQDN/IP allowlisting (NAT Gateway behind a firewall, NVA, proxy, etc.), you can permit egress directly to ECR Public rather than mirroring the image. This is a viable shortcut when an approved egress path already exists, but it leaves the runtime image pull dependent on AWS ECR Public's availability and on internet routing — which is why the [private mirror pattern](#aws-private-mirror-pattern) above is recommended for most environments.

The following destinations must be reachable on TCP 443:

| Destination | Purpose | Source |
|---|---|---|
| `public.ecr.aws` | ECR Public registry / CloudFront | [AWS ECR Public docs](https://docs.aws.amazon.com/AmazonECR/latest/public/what-is-ecr.html) |
| `ecr-public.us-east-1.amazonaws.com` and/or `api.ecr-public.us-east-1.amazonaws.com` | ECR Public API (auth + manifest) | [AWS ECR Public endpoints reference](https://docs.aws.amazon.com/general/latest/gr/ecr-public.html) |
| Regional starport S3 bucket — pattern `prod-<region>-starport-layer-bucket.s3.<region>.amazonaws.com` | Image layer blob downloads | [AWS ECR VPC endpoints](https://docs.aws.amazon.com/AmazonECR/latest/userguide/vpc-endpoints.html) |

If your firewall does not support FQDN-based rules, you must determine the IP ranges yourself from AWS's published [`ip-ranges.json`](https://docs.aws.amazon.com/general/latest/gr/aws-ip-ranges.html) (filter by `S3`, `CLOUDFRONT`, and `EC2` for the relevant regions). Matillion does not maintain a static IP allowlist; AWS rotates ranges over time, and any list captured here would go stale.

---

## Azure — Symptoms of an image pull failure

If you're investigating a suspected image-pull problem in an Azure deployment, the following are the typical signals:

**Azure Container Apps:**
- Revision activation fails; portal shows the revision in a `Failed` state with an `ImagePullFailure` system event
- Activity Log / revision events show messages like `Failed to pull image "...": dial tcp: i/o timeout` or `... no route to host`
- `ContainerAppSystemLogs_CL` in Log Analytics records the pull failure
- Application logs never appear because the container never starts

**Azure Kubernetes Service (AKS):**
- `kubectl describe pod` shows events: `Failed to pull image "...": rpc error: ... failed to resolve reference: ... dial tcp <ip>:443: i/o timeout`
- Pod cycles through `ErrImagePull` → `ImagePullBackOff`
- `KubeEvents` / `ContainerLog` in Log Analytics capture the same events (with Container Insights enabled)
- `kube_pod_status_reason{reason="ImagePullBackOff"}` is visible in Azure Monitor managed Prometheus

For AKS clusters, the `outboundType` setting controls egress posture: `loadBalancer` (default), `managedNATGateway`, `userAssignedNATGateway`, or `userDefinedRouting` (UDR forces traffic through Azure Firewall / NVA — typical for zero-egress).

If these match what you're seeing, work through the configuration paths below.

---

## Azure — Private Mirror Pattern (Recommended) {#azure-private-mirror-pattern}

For Azure deployments — and especially if you are in a regulated or restricted-network environment — the recommended approach is to mirror the Runner image into a customer-managed ACR in your deployment region, then expose that ACR to your AKS / Container Apps VNet via a Private Endpoint. Your workloads pull privately with no internet egress required, and the pattern aligns with how most enterprise teams already manage container images.

This is preferred over the egress/whitelisting approaches below because it gives you full control over the registry path, simpler operational reasoning, and a clean fit with Azure Private Link semantics your security team will already be familiar with.

### Steps

1. **Provision a customer-managed ACR Premium SKU** (Premium is required for Private Endpoint support — see [Set up Private Endpoint with Private Link for ACR](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-private-link)) in your deployment region.
2. **Mirror the image into your ACR.** From a host with internet access:
   ```
   az acr import \
     --name <yourAcr> \
     --source matillion.azurecr.io/cloud-agent:current \
     --image cloud-agent:current
   ```
   `az acr import` runs server-side from Microsoft's network — no Docker engine required on the executing host. Alternatively, use `docker pull` + `docker push` from a build host.
3. **Disable public network access** on your ACR (per Microsoft's recommendation when using Private Link).
4. **Create a Private Endpoint** for your ACR in the AKS / Container Apps VNet, with `--group-ids registry`.
5. **Configure the private DNS zone** `privatelink.azurecr.io` and link it to the VNet. Both the registry endpoint (`<yourAcr>.azurecr.io`) and the regional data endpoint (`<yourAcr>.<region>.data.azurecr.io`) are A-records inside this single zone.
6. **Grant pull access** to your AKS managed identity or Container Apps workload identity via the `AcrPull` role assignment on your ACR (no `imagePullSecrets` required).
7. **Override the Helm chart's image reference**: set `image.repository` to `<yourAcr>.azurecr.io/cloud-agent` (or your chosen path).
8. **Establish a refresh process** to re-import the image against Matillion's release cadence.

### Azure alternative: ACR Artifact Cache

Microsoft's [Artifact Cache](https://learn.microsoft.com/en-us/azure/container-registry/artifact-cache-overview) feature on the customer-managed ACR officially supports `public.ecr.aws` as an upstream with unauthenticated pulls (Microsoft lists *"AWS Elastic Container Registry (ECR) Public Gallery"* as a supported source). Egress to the upstream happens from Microsoft's managed control plane, not from your VNet — your VNet can remain fully locked down even on first pull.

Caveat (per Microsoft's docs): *"Currently, artifact cache doesn't automatically pull new tags of images when a new tag is available."* You must trigger refreshes or accept on-demand pull semantics.

### Required Azure components summary

| Component | Purpose |
|---|---|
| Customer-managed ACR (Premium SKU) | Private registry to host the mirrored image |
| Private Endpoint, subresource `registry` | Private connectivity from VNet to ACR |
| Private DNS Zone `privatelink.azurecr.io` (linked to VNet) | DNS resolution for ACR FQDNs to private IPs |
| `AcrPull` role assignment on managed/workload identity | Pull authentication without `imagePullSecrets` |
| Helm `image.repository` override | Points the deployment at your ACR |

---

## Azure — Whitelisted Egress (Alternative) {#azure-allowlist}

If your environment uses an internet-reachable egress path with FQDN/IP allowlisting (NAT Gateway, Azure Firewall, proxy, etc.), you can permit egress directly to Matillion's public ACR rather than mirroring it. This is a viable shortcut when an approved egress path already exists, but it leaves the runtime image pull dependent on Matillion's public ACR availability and on internet routing — which is why the [private mirror pattern](#azure-private-mirror-pattern) above is recommended for most environments.

### Azure Firewall application rules with explicit FQDNs

Per Microsoft's [ACR firewall access rules documentation](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-firewall-access-rules), pin Azure Firewall application rules to:

| Destination | Purpose |
|---|---|
| `matillion.azurecr.io` | ACR REST endpoint (auth + manifest) |
| `matillion.<region>.data.azurecr.io` | Regional data endpoint (image layer downloads) |

Where `<region>` is the Azure region the ACR is hosted in. Confirm the actual region via `nslookup matillion.azurecr.io` from a node with public DNS access; Matillion does not publish this region as a static fact and it can change.

Pinning rules to these specific FQDNs (rather than to a wildcard like `*.azurecr.io`) gives least-privilege access — the workload can only reach Matillion's ACR, not arbitrary other Azure-hosted registries.

### `AzureContainerRegistry` service tag

If your environment uses NSGs or a firewall that supports Azure service tags but not FQDN rules, the [`AzureContainerRegistry` service tag](https://learn.microsoft.com/en-us/azure/virtual-network/service-tags-overview) covers all Azure-hosted ACR public IPs (regional scoping is supported). Note Microsoft's caveat: this tag does **not** isolate access to Matillion's ACR — it permits egress to *any* Azure-hosted ACR. Prefer FQDN-based application rules where supported.

### Cross-tenant Private Endpoint to Matillion's ACR — requires Matillion approval (not currently offered)

Azure Container Registry technically supports cross-tenant Private Endpoints, but per the [Private Endpoint overview](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-overview) the connection requires the registry owner to provision and approve it. **Matillion does not currently provision or approve Private Endpoints from your VNet to `matillion.azurecr.io`.** If you need Private Link semantics for ACR access, use the private mirror pattern above — operate a customer-managed ACR with your own Private Endpoint, populated via Artifact Cache or a manual mirror.

There is also no Microsoft-supported way for an ACR owner to expose their registry through Azure Private Link Service for arbitrary third-party consumers; ACR is exposed as a first-party private-link resource type only.

---

## Bundled Prometheus images (Helm-based deployments only)

If you install the optional Prometheus monitoring chart at `agent/helm/prometheus`, your cluster also pulls third-party images from public registries other than the Runner image source:

| Image | Default registry | Notes |
|---|---|---|
| `prom/prometheus:v2.22.0` | Docker Hub (`docker.io`) | Prometheus server |
| `gcr.io/k8s-staging-prometheus-adapter/prometheus-adapter-amd64:v0.12.0` | Google Container Registry (`gcr.io`) | Kubernetes metrics adapter |
| `curlimages/curl:8.5.0` | Docker Hub (`docker.io`) | Init container used for readiness checks across deployments |

These registries are global and do not have the AWS-specific single-region anchoring that `public.ecr.aws` has — but they still require an internet-reachable path from your cluster nodes to the relevant public endpoints.

The same egress decision tree applies:

- **Open or whitelisted egress:** permit outbound HTTPS to `docker.io` / `registry-1.docker.io` (and Docker Hub's CDN: `*.cloudflare.docker.com` and `production.cloudflare.docker.com`) and to `gcr.io` (and `storage.googleapis.com` for layer downloads). Confirm exact endpoints from the registry providers' own documentation, as both have evolved over time.
- **Zero or restricted egress:** mirror these images into the same customer-managed private registry that hosts your Runner image, then override the Helm chart's image references for each component.

The Prometheus Helm chart at `agent/helm/prometheus` exposes image-repository values that can be overridden in your values file. If you are mirroring the Runner image into a private registry for a zero-egress deployment, plan to mirror these images at the same time so the full stack pulls from a single internal source.

> **Note:** Docker Hub also enforces anonymous pull rate limits that can affect production clusters during scale events even when egress is open. Mirroring to a private registry is a good practice regardless of egress posture for that reason.

---

## Control plane connectivity (related but separate)

Independent of image pull, the Runner must maintain connectivity to the Matillion SaaS control plane. Two supported paths exist:

- **Public connectivity** — your environment's egress (NAT Gateway, Azure Firewall, NVA, proxy) reaches the Matillion control plane FQDNs over the internet
- **Private Link** — AWS PrivateLink or Azure Private Endpoint to the Matillion platform endpoint

If you use Private Link for the control plane, you likely have no general internet egress — in which case the private mirror pattern above is unavoidable. If you use firewall whitelisting for the control plane, you likely already have the kind of egress path that makes the whitelist option viable for image pulls too.

---

## References

- [Amazon ECR Public endpoints and quotas (AWS General Reference)](https://docs.aws.amazon.com/general/latest/gr/ecr-public.html)
- [Amazon ECR interface VPC endpoints (AWS PrivateLink)](https://docs.aws.amazon.com/AmazonECR/latest/userguide/vpc-endpoints.html)
- [Amazon ECR pull-through cache](https://docs.aws.amazon.com/AmazonECR/latest/userguide/pull-through-cache.html)
- [Set up Private Endpoint with Private Link for ACR](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-private-link)
- [ACR firewall access rules](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-firewall-access-rules)
- [Optimize image pulls with artifact cache in Azure Container Registry](https://learn.microsoft.com/en-us/azure/container-registry/artifact-cache-overview)
- [Azure Private Endpoint overview](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-overview)
- [Azure service tags overview](https://learn.microsoft.com/en-us/azure/virtual-network/service-tags-overview)
