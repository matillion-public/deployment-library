# Azure Kubernetes Service (AKS) Deployment with Terraform

This repository contains Terraform configurations for deploying an Azure Kubernetes Service (AKS) cluster along with associated resources such as a User Assigned Managed Identity, Log Analytics Workspace, Storage Account, and Key Vault.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Configuration Files](#configuration-files)
  - [main.tf](#maintf)
  - [variables.tf](#variablestf)
  - [outputs.tf](#outputstf)
- [Usage](#usage)
- [Key Vault name](#key-vault-name)
- [Outputs](#outputs)

## Prerequisites

- Azure CLI installed and authenticated
- Terraform installed
- An Azure subscription
- Service Principal for Key Vault access (see [Service Principal Setup](#service-principal-setup))

## Configuration Files

### main.tf

Defines the main resources for the deployment including:
- Azure Kubernetes Service (AKS) Cluster
- User Assigned Managed Identity
- Log Analytics Workspace (optional, `enable_container_insights`)
- Storage Account
- Key Vault
- Role Assignments

### variables.tf

Defines the input variables used in the Terraform configurations:
- `name`: Name prefix for resources
- `location`: Azure region for resources
- `resource_group_name`: Resource group name
- `subnet_id`: Subnet ID for AKS
- `appgw_subnet_id`: Subnet ID for Application Gateway
- `tags`: Tags to apply to resources
- `desired_node_count`: Desired number of nodes in the AKS cluster
- `node_pool_zones`: Availability zones for the default node pool (see [Availability zones](#availability-zones))
- `workload_identity_enabled`: Enable the OIDC issuer and workload identity addon
- `create_runner_identity`: Create the shared, vault-wide runner identity when workload identity is on; set false on a shared cluster (see [Workload identity on a shared cluster](#workload-identity-on-a-shared-cluster))
- `network_plugin_mode`: `overlay` for Azure CNI Overlay; null (default) keeps node-subnet mode (see [Pod networking](#pod-networking))
- `pod_cidr`: Pod address range under overlay; null uses the AKS default
- `network_policy`: Engine that enforces NetworkPolicy objects (`azure`, `calico`, `cilium`); null (default) installs none (see [Network policy](#network-policy))
- `network_data_plane`: `azure` (default) or `cilium`
- `key_vault_administrator_principal_ids`: Object IDs granted Key Vault Administrator on the vault; null (default) grants the identity running Terraform (see [Key Vault administrators](#key-vault-administrators))
- `azure_rbac_enabled`: Enable Entra ID integration with Azure RBAC for Kubernetes; false (default) keeps no Entra integration (see [Cluster access](#cluster-access))
- `admin_group_object_ids`: Entra ID group object IDs bound to cluster-admin; only used with `azure_rbac_enabled = true`
- `local_account_disabled`: Disable local accounts and the admin kubeconfig; requires `azure_rbac_enabled = true`
- `enable_container_insights`: Create a Log Analytics workspace and connect the cluster to it (Container Insights); false (default) creates neither (see [Container Insights](#container-insights))
- `random_string_salt`: Random string for uniqueness
- `is_private_cluster`: Boolean to enable private cluster
- `authorized_ip_ranges`: List of authorized IP ranges for API server
- `app_gw_id`: Application Gateway ID
- `service_principal_client_id`: Service Principal Client ID for Key Vault access
- `service_principal_secret`: Service Principal Secret for Key Vault access

### outputs.tf

Defines the outputs of the Terraform configurations:
- `kubeconfig`: Path to the Kubernetes configuration file
- `cluster_name`: Name of the AKS cluster
- `aks_identity_principal_id`: Principal ID of the User Assigned Managed Identity
- `log_analytics_workspace_id`: ID of the Container Insights workspace, or null when `enable_container_insights` is false
- `log_analytics_workspace_name`: Name of the Container Insights workspace, or null when `enable_container_insights` is false

## Availability zones

The default node pool is created without zones unless `node_pool_zones` is set.
A zone-unaware pool can place every node — and therefore every runner replica —
in a single availability zone, so one zone outage takes the whole runner down.

For a **new** cluster, set the zones your region supports and enable pod-level
spread in the Helm values so the replicas actually use them:

```hcl
node_pool_zones = ["1", "2", "3"]
```

`desired_node_count` must be at least the number of zones, because the autoscaler
floor defaults to one node per zone; the plan fails otherwise.

```yaml
# runner/helm/runner values
topologySpread:
  enabled: true
podDisruptionBudget:
  enabled: true
```

Node pool zones alone only guarantee the *nodes* span zones; without
`topologySpread` the scheduler is still free to stack every replica on one node's
zone. The two changes are only meaningful together.

### Storage replication

`storage_account_replication_type` controls the staging storage account and
defaults to `LRS`, which keeps a single copy in a single zone. Once the node pool
spans zones this is the remaining single-zone dependency, so new deployments
should set `ZRS`.

Changing it on an account that already holds data is an **Azure conversion**, not
a Terraform edit — use Azure's customer-initiated conversion or a manual
migration, and only then update the Terraform value so state matches reality.
Do not let a `terraform apply` be the first thing that attempts it.

### Migrating an existing cluster

**A node pool's zones are immutable in Azure.** Setting `node_pool_zones` on a
cluster that already exists produces a plan that *replaces* the default node
pool, which destroys every node it currently runs. Do not apply that plan against
a live deployment.

The supported path is to add a new zonal pool alongside the existing one and move
the workload:

1. Add a second `azurerm_kubernetes_cluster_node_pool` with the desired `zones`.
2. `kubectl cordon` the old nodes so nothing new schedules onto them.
3. `kubectl drain` them one at a time. Respect the runner's termination grace
   period — a runner pod may take up to 12 hours to finish in-flight tasks, and
   draining faster than that turns a lossless failover into a lossy one. Enable
   `podDisruptionBudget` first so the drain cannot take every replica at once.
4. Once the old pool is empty, remove it and set `node_pool_zones` on the default
   pool, confirming with `terraform plan` that nothing else is being replaced.

## Workload identity on a shared cluster

With `workload_identity_enabled` (the default) the module turns on the cluster's
OIDC issuer and workload identity addon, and also creates one shared runner
identity, federated to the runner and script-runner service accounts in
`namespace`. That identity holds `Key Vault Secrets User` and `Reader` on the
whole vault, `Reader` on the subscription (unless `grant_runner_subscription_reader = false`) and `Storage Blob Data Contributor` on
the staging account — right for one runner, wrong once the cluster and vault
are shared between tenants.

On a shared cluster, give each tenant its own identity with
[`modules/azure/runner-identity`](../runner-identity/readme.md) and turn the
shared one off while keeping workload identity on:

```hcl
workload_identity_enabled = true
create_runner_identity    = false
```

`runner_workload_identity_client_id` is then empty; take each tenant's client
ID from its `runner-identity` module instead.

Setting `create_runner_identity = false` on an existing deployment **destroys**
the shared identity, its grants and its federated credentials. Move every runner
onto a per-tenant identity first, or it loses access to Key Vault and storage
on the next apply.

### Role assignment principal type

The module sets `principal_type = "ServicePrincipal"` on the role assignments
for the cluster identity and the shared runner identity, so Azure does not look
the principal up in Entra ID before assigning the role.

On existing deployments `terraform plan` shows no change for these assignments.
In a test on 2026-11-13 (seven assignments), Azure and Terraform state already
stored `principalType` as `ServicePrincipal` for all seven, the plan of the
changed configuration showed no changes, and the apply was 0 added, 0 changed,
0 destroyed.

Role assignments that Azure stored with an empty `principalType` were not
tested. For such a deployment, run `terraform plan` before applying and check
the action on each role assignment. Do not apply a plan that replaces a role
assignment without reviewing it.

## Pod networking

The cluster uses Azure CNI. By default it runs in **node-subnet mode**: every
pod takes an address from the node subnet, and each node reserves addresses for
its maximum pod count when it joins. The subnet therefore has to hold every node
*and* every pod those nodes could run. On a shared cluster, where many tenants'
runners and script runners scale independently, the subnet fills long before
the nodes run out of capacity, and the autoscaler can no longer add nodes.

**Azure CNI Overlay** gives pods addresses from a private range that is not part
of the VNet, so the node subnet only needs to be sized for nodes. Set it on new
clusters:

```hcl
network_plugin_mode = "overlay"
pod_cidr            = "10.244.0.0/16" # optional; this is the AKS default
```

`pod_cidr` must not overlap the VNet, the service CIDR (`10.2.0.0/16`) or any
network the runner has to reach, such as a peered data warehouse VNet. Pod
traffic leaving the cluster is SNATed to the node's address, so firewall rules
on the far side keep matching the node subnet.

### Existing clusters

Both inputs default to null, so an existing cluster plans clean after upgrading
the module. Changing them later is not a Terraform-only edit:

- Adding `network_plugin_mode = "overlay"` to a node-subnet cluster is an
  in-place Azure CNI migration that **reimages every node**. Follow Azure's
  [Azure CNI upgrade guidance](https://learn.microsoft.com/azure/aks/update-azure-cni),
  enable the runner's `podDisruptionBudget` first, and do not let a
  `terraform apply` be the first thing that attempts it.
- Removing it again, or changing `pod_cidr` once set, **replaces the cluster**.

### Network policy

The runner chart creates NetworkPolicy objects by default
(`networkPolicy.enabled: true`) to limit what runner and script-runner pods can
reach. Kubernetes only stores those objects; a **network policy engine** enforces
them. Without `network_policy` set the cluster has no engine, the policies do
nothing, and on a shared cluster one tenant's pods can reach another's.

Microsoft recommends Cilium, which is one choice made in two inputs and runs on
overlay:

```hcl
network_plugin_mode = "overlay"
network_policy      = "cilium"
network_data_plane  = "cilium"
```

The module fails the plan if `network_policy = "cilium"` and
`network_data_plane = "cilium"` are not set together, or if the Cilium data plane
is chosen without overlay — Azure runs it only on overlay or a dedicated pod
subnet, and this module offers overlay. `calico` and `azure` run on the default
`azure` data plane in either networking mode. Azure Network Policy Manager
(`azure`) loses support on Linux nodes on 30 September 2028, so prefer Cilium
for new clusters.

On an existing cluster:

- Adding `calico` or `azure` installs the engine in place but **reimages every
  node pool at once**.
- Moving the data plane from `azure` to `cilium`, or the policy from `azure` or
  `calico` to `cilium`, is an in-place upgrade that reimages every node. See
  [Upgrade to Azure CNI Powered by Cilium](https://learn.microsoft.com/azure/aks/upgrade-aks-ipam-and-dataplane).
- Changing to any other engine **replaces the cluster**. Setting
  `network_policy` back to null does not remove an installed engine: the
  provider reads the current engine back and plans no change.

## Key Vault administrators

Teams and CI should set `key_vault_administrator_principal_ids` to the object
IDs of the users, groups or service principals that administer the vault.

- Unset (default): Key Vault Administrator goes to the identity that last ran
  `terraform apply`. A second operator's apply replaces the first operator's
  grant.
- Set: the grant to the identity running Terraform is removed and one grant is
  created per listed ID. The applying identity must be in the list or hold
  another way to manage the vault (Owner or User Access Administrator alone
  does not read or write secrets), or later applies that need data-plane
  access to the vault fail.
- Empty set: the vault has no Key Vault Administrator from this module.

Values must be known at plan time; IDs of principals created in the same apply
fail with Terraform's `for_each` error.

Upgrading an existing deployment:

- Variable unset: a `moved` block moves the state address from
  `azurerm_role_assignment.current_client_key_vault_admin` to
  `azurerm_role_assignment.current_client_key_vault_admin[0]`. The plan shows no
  change to the assignment.
- Variable set: the plan destroys
  `azurerm_role_assignment.current_client_key_vault_admin[0]` and creates one
  `azurerm_role_assignment.key_vault_administrators["<id>"]` per ID. The
  current operator loses Key Vault Administrator unless listed.
- Setting the variable and later unsetting it destroys the listed grants and
  recreates the grant to the identity running Terraform.

When the applying identity is listed, the old and new grants have the same
principal, role and scope, which Azure allows only once. `key_vault_administrators`
depends on `current_client_key_vault_admin`, so Terraform finishes the destroy
before the create in both directions. If Azure still returns
`RoleAssignmentExists` (409) because the delete has not propagated, run
`terraform apply` again; the destroy is already recorded in state and the second
apply only creates the missing grant.

## Cluster access

By default local accounts are enabled and the cluster has no Entra ID
integration. Anyone with Contributor on the cluster
(`Microsoft.ContainerService/managedClusters/listClusterAdminCredential/action`)
can run `az aks get-credentials --admin` and get a kubeconfig whose client
certificate is `O=system:masters, CN=masterclient`. The credential is not tied
to the caller, keeps working after the caller's role is removed until the
cluster certificates are rotated, and Kubernetes audit logs record
`masterclient`.

Three inputs change this. All are off by default:

```hcl
azure_rbac_enabled     = true
admin_group_object_ids = ["<group object id>"]
local_account_disabled = true
```

- `azure_rbac_enabled = true` enables Entra ID integration with Azure RBAC for
  Kubernetes authorization.
- `admin_group_object_ids` lists Entra ID groups whose members get
  cluster-admin. It may be empty, in which case access comes only from Azure
  role assignments on the cluster. Setting it without `azure_rbac_enabled`
  fails the plan.
- `local_account_disabled = true` removes the admin kubeconfig. It requires
  `azure_rbac_enabled = true`, and the plan fails without it.

With Entra integration on, users, operators and `az aks command invoke` callers
need an Azure RBAC role on the cluster (for example Azure Kubernetes Service
RBAC Cluster Admin, or the Reader, Writer and Admin variants) or membership of
a group in `admin_group_object_ids`. kubectl and helm need `kubelogin`:

```bash
az aks get-credentials -g <resource group> -n <cluster>
kubelogin convert-kubeconfig -l azurecli
```

The Terraform principal that later installs the Helm release needs the same
access. This module creates no role assignments: grant the roles outside this
configuration.

When the provider returns no usable kube_config, which is the case with local
accounts disabled, the `k8s_host`, `client_certificate`, `client_key` and
`cluster_ca_certificate` outputs are empty strings.

### Existing clusters

- With the defaults the plan shows no change.
- Enabling Entra integration or disabling local accounts on a live cluster
  changes how every user authenticates. Grant the roles and confirm access
  through Entra before setting `local_account_disabled = true`.
- Whether enabling Entra integration on an existing cluster is an in-place
  update or a replacement has not been measured. Read the plan before applying.
- Treat enabling Entra integration as one-way. Azure documents that AKS-managed Entra integration cannot be disabled once it is enabled. Setting `azure_rbac_enabled` back to `false` after an apply is not a supported way back, and the provider's response to removing the block has not been checked.
- The defaults are expected to change in a later breaking release.

## Key Vault name

The default Key Vault name is `name`, `-` and the 6-character salt, cut at 24
characters, the Azure limit for a vault name. A `name` longer than 17 characters
loses salt characters:

| `name` length | Salt characters kept |
|---|---|
| 17 or fewer | 6 |
| 18 | 5 |
| 22 | 1 |
| 23 | none; the vault name ends in `-` and the plan fails |
| 24 or more | none |

Vault names are global across Azure, and a deleted vault keeps its name for the
soft-delete retention period (7 days in this module). Fewer salt characters
make a collision with another deployment, or with a vault destroyed in the last
7 days, more likely.

A `name` of 18 characters or more gives a warning at plan (`Check block
assertion failed`). A derived vault name that ends in `-` fails the plan. Both
checks read only `name` and assume the 6-character alphanumeric salt that
`runner/azure/aks` generates, so they run at plan on a new deployment, before
the salt exists. Setting `resource_names["key_vault"]`, for example from
[`modules/azure/naming`](../naming), replaces the default name and skips both
checks.

Effect on existing deployments:

- `name` of 17 characters or fewer: no change.
- `name` of 18 to 22 characters: a warning at every plan. The vault name and
  the planned changes are unchanged, and the plan exits 0. Do not shorten
  `name` to clear the warning: changing the vault name replaces the vault.
- `name` of 23 characters: the plan fails. Azure rejects a vault name ending in
  `-`, so no existing deployment can use this name with the default vault name.
- `name` of 24 or more characters: a warning, and the vault name has no salt.
  A `name` whose 24th character is `-` fails the plan.
- Terraform 1.2 to 1.4: `terraform init` fails on the version constraint. The
  module now needs Terraform 1.5 or later for the `check` block.

## Container Insights

`enable_container_insights = true` creates a Log Analytics workspace (`PerGB2018`)
and adds an `oms_agent` block to the cluster, so pod logs and node and
container metrics reach Azure Monitor. Ingested data is billed. With the
default, false, the module creates no workspace and the cluster has no
`oms_agent` block. The `log_analytics_workspace_id` and
`log_analytics_workspace_name` outputs are null in that case. The
`log_workspace` key in `resource_names` still names the workspace when it is
enabled.

### Existing deployments

- The next `terraform plan` with the default shows one resource to destroy:
  the unused, empty `azurerm_log_analytics_workspace.aks_log_workspace`
  (listed as moved to `[0]`, then destroyed), and no change to the cluster. The
  destroyed workspace stays soft-deleted in Azure for 14 days and can be listed
  with `az monitor log-analytics workspace list-deleted-workspaces`.
- To keep or gain monitoring, set `enable_container_insights = true` before
  applying. The existing workspace is kept (a `moved` block maps it to `[0]`)
  and the cluster gets an `oms_agent` block.
- If the workspace was connected outside Terraform, for example with
  `az aks enable-addons --workspace-resource-id`, applying with the default
  plans to destroy the workspace the addon writes to. Set
  `enable_container_insights = true` before applying. Whether Terraform also
  plans to remove the out-of-band addon from the cluster has not been checked.

## Service Principal Setup

To create the required Service Principal for Key Vault access, follow these steps:

### 1. Create the Service Principal

```bash
# Create a Service Principal
az ad sp create-for-rbac --name "matillion-runner-keyvault-sp" --role "Key Vault Secrets User" --scopes "/subscriptions/{subscription-id}/resourceGroups/{resource-group-name}/providers/Microsoft.KeyVault/vaults/{key-vault-name}"
```

This command will output:
```json
{
  "appId": "<your-service-principal-app-id>",
  "displayName": "matillion-runner-keyvault-sp",
  "password": "<your-service-principal-password>",
  "tenant": "<your-tenant-id>"
}
```

### 2. Update terraform.tfvars

Add the Service Principal credentials to your `terraform.tfvars` file (ensure this file is in `.gitignore`):

```hcl
# Service Principal for Key Vault Access
service_principal_client_id = "<your-service-principal-app-id>"
service_principal_secret    = "<your-service-principal-password>"
```

### 3. Additional Permissions (if needed)

If you encounter permission issues, you may need to grant additional roles:

```bash
# Grant Key Vault Secrets Officer role (if needed for secret management)
az role assignment create \
  --assignee "<your-service-principal-app-id>" \
  --role "Key Vault Secrets Officer" \
  --scope "/subscriptions/{subscription-id}/resourceGroups/{resource-group-name}/providers/Microsoft.KeyVault/vaults/{key-vault-name}"

# Grant Reader role for Key Vault metadata access
az role assignment create \
  --assignee "<your-service-principal-app-id>" \
  --role "Reader" \
  --scope "/subscriptions/{subscription-id}/resourceGroups/{resource-group-name}/providers/Microsoft.KeyVault/vaults/{key-vault-name}"
```

**⚠️ CRITICAL SECURITY WARNING:**
- **NEVER commit real Service Principal credentials to version control**
- Replace all placeholder values (`<your-*>`) with actual credentials only in your local `terraform.tfvars` file
- Add `terraform.tfvars` to your `.gitignore` file to prevent accidental commits
- Store the Service Principal secret securely using Azure Key Vault or environment variables
- Rotate credentials regularly
- Apply principle of least privilege
- Use Azure Workload Identity or Managed Identity when possible instead of Service Principal credentials

## Outputs
After applying the Terraform configurations, the following outputs will be available:

- kubeconfig: Path to the Kubernetes configuration file for use with kubectl
- cluster_name: Name of the deployed AKS cluster
- aks_identity_principal_id: Principal ID of the User Assigned Managed Identity
- k8s_host, client_certificate, client_key, cluster_ca_certificate: empty strings when the provider returns no usable kube_config (local accounts disabled)