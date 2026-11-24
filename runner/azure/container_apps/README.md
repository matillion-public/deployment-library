# Azure Container Apps Deployment for Matillion Runner

This directory contains Terraform configurations for deploying the Matillion Maia Runner using Azure Container Apps - a fully managed serverless container service.

## Overview

Azure Container Apps deployment provides:
- **Serverless Containers**: Fully managed container hosting
- **Fixed Replica Count**: Consistent container count (no auto-scaling - that is a K8s/AKS feature)
- **Integrated Security**: Managed Identity, Key Vault, and network isolation
- **Cost Effective**: Pay-per-use pricing model
- **Full Prerequisite Creation**: VNet, subnets, identity, Key Vault, and storage are all created automatically

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  Azure Resource Group                    │
│                                                         │
│  ┌─────────────────────────────────────────────────────┐│
│  │  Virtual Network (10.0.0.0/16)                      ││
│  │  ┌────────────────────────┐ ┌─────────────────────┐ ││
│  │  │ Subnet 0 (10.0.0.0/23)│ │Subnet 1 (10.0.2.0/24│ ││
│  │  │ Delegated to           │ │ Service endpoints    │ ││
│  │  │ Microsoft.App/         │ │ (Storage, KeyVault)  │ ││
│  │  │ environments           │ │                      │ ││
│  │  └──────────┬─────────────┘ └─────────────────────┘ ││
│  └─────────────┼───────────────────────────────────────┘│
│                │                                         │
│  ┌─────────────▼───────────────────────────────────────┐│
│  │    Container Apps Environment                        ││
│  │  ┌───────────────────────────────────────┐          ││
│  │  │  Container App (Matillion Runner)      │          ││
│  │  │  - UserAssigned Managed Identity      │          ││
│  │  │  - Workload Profile: agentpool         │          ││
│  │  │    (D4 for small/medium/large; D8 for   │          ││
│  │  │    xlarge — driven by runner_size)       │          ││
│  │  │  - Replicas: 2 (fixed)               │          ││
│  │  └───────────────────────────────────────┘          ││
│  └─────────────────────────────────────────────────────┘│
│                                                         │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────────┐│
│  │  Key Vault   │ │   Storage    │ │  Log Analytics   ││
│  │  (Secrets)   │ │  Account     │ │  Workspace       ││
│  └──────────────┘ └──────────────┘ └──────────────────┘│
└─────────────────────────────────────────────────────────┘
```

## Module Structure

This deployment follows the same modular pattern as the AKS deployment:

```
runner/azure/container_apps/     # Root configuration
├── main.tf                     # Calls networking + container-apps modules
├── variables.tf                # Input variables
├── outputs.tf                  # Output values
├── provider.tf                 # Azure provider config
├── backend.tf                  # State backend config
└── terraform.example.tfvars    # Example variable values

modules/azure/networking/       # Shared networking module
├── main.tf                     # VNet, subnets, NSG, NAT Gateway
├── variables.tf
└── outputs.tf

modules/azure/container-apps/   # Container Apps module
├── main.tf                     # CA env, app, KV, storage, identity, roles
├── variables.tf
└── outputs.tf
```

## Prerequisites

- [Terraform 1.5+](https://www.terraform.io/downloads.html)
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- Azure subscription with Container Apps enabled
- A pre-existing resource group

### Image Delivery & Network Requirements

The Runner image for this deployment is pulled from `matillion.azurecr.io/cloud-agent` — a Matillion-operated public Azure Container Registry with anonymous pull. Your Container Apps environment must have network access to that registry — via open egress, a whitelisted egress path, or a customer-managed private mirror for zero-egress environments.

See [Network Requirements for Pulling the Runner Image](../../../blogs/runner-image-pull-network-requirements.md) for supported network patterns, including the customer-managed ACR + Private Endpoint pattern and ACR Artifact Cache as a managed alternative.

### Required Azure Permissions

```bash
# Login to Azure
az login

# Set subscription
az account set --subscription "your-subscription-id"

# Register required providers
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.OperationalInsights
```

The principal that runs Terraform needs:

- On the resource group: permission to create the resources in this deployment
  (for example Contributor), and `Microsoft.Authorization/roleAssignments/write`
  and `/delete` (for example Role Based Access Control Administrator or User
  Access Administrator). The deployment assigns roles on the Key Vault and the
  storage account it creates, to the runner identity and to the Key Vault
  administrators.
- On the container registry, when `container_acr_id` or `script_runner_acr_id`
  is set: `Microsoft.Authorization/roleAssignments/write` and `/delete`, to
  assign AcrPull to the runner or script runner identity.
- On the subscription: permission to register the resource providers above, if
  they are not registered yet.

No role assignment is created at subscription scope.

### Upgrading: AcrPull scope

Earlier versions assigned AcrPull to the runner identity at subscription scope
when `container_acr_id` was not set. That assignment is no longer created.

- `container_acr_id` not set (the default): the next plan destroys one resource,
  `module.container_apps.azurerm_role_assignment.acr_pull[0]` (moved from
  `azurerm_role_assignment.acr_pull`), the subscription-scope AcrPull
  assignment. Nothing else changes. The apply needs
  `Microsoft.Authorization/roleAssignments/delete` at subscription scope. A
  principal without it can have an administrator delete the assignment
  (`az role assignment delete`) and then run
  `terraform state rm 'module.container_apps.azurerm_role_assignment.acr_pull'`
  before the next plan.
- `container_acr_id` set: no change. The assignment keeps its registry scope and
  moves to the address `acr_pull[0]` in state.
- A deployment that pulls the runner image from a private registry must set
  `container_acr_id`. Without it the image pull is anonymous, which a private
  registry rejects whether or not the subscription assignment exists.

### Upgrading: HTTPS inbound rule

Earlier versions created an NSG rule `AllowHTTPS` allowing TCP 443 from any
source. It is now created only when `https_inbound_source_prefixes` is set.

- `https_inbound_source_prefixes` not set (the default): the next plan updates
  `module.networking.azurerm_network_security_group.nsg` in place, removing the
  rule. Nothing is replaced or destroyed. No Container App in this deployment
  accepts traffic from outside the VNet, so the runner is not affected.
- To keep the rule, set `https_inbound_source_prefixes = ["*"]`, which plans no
  change.

### Upgrading: workload profile capacity check

Plan now fails when the requested vCPU (`replica_count` runner replicas plus the
script runner replica when `enable_script_runner = true`) is more than
`workload_profile_max_count` times the vCPU of the workload profile type. See
Container Sizing.

- Configurations whose replicas fit: no plan change.
- A deployment whose requested vCPU exceeds the profile capacity (for example
  `runner_size = "large"`, `replica_count = 2`, `workload_profile_max_count = 1`)
  applied before with a degraded revision and fewer running replicas than
  requested. Its next plan fails with the capacity message until
  `workload_profile_max_count` is raised or `replica_count` is lowered. Nothing is
  replaced or destroyed.
- Raising `workload_profile_max_count` is an in-place update of the Container
  App Environment and can add instances, which adds cost.

## Networking Requirements

### Container Apps Subnet Restrictions

Azure Container Apps has specific subnet requirements that differ from AKS. This deployment handles them automatically via `cidrsubnet()`, but they are important to understand:

| Requirement | Detail |
|---|---|
| **Minimum subnet size** | `/23` (512 addresses). Azure reserves addresses for internal Container Apps infrastructure. A `/24` or smaller **will fail deployment**. |
| **Recommended subnet size** | `/23` for most workloads. Use `/21` if you expect many Container App environments or revisions. |
| **Subnet delegation** | The subnet **must** be delegated to `Microsoft.App/environments`. No other resources can share this delegated subnet. |
| **Dedicated subnet** | The Container Apps Environment subnet cannot be shared with other services (e.g. VMs, AKS, Application Gateway). |
| **Service endpoints** | `Microsoft.Storage` and `Microsoft.KeyVault` are configured for Key Vault and storage access. |
| **NSG** | An NSG is attached to all subnets. By default it has no rule of its own, so the Azure default rules apply: inbound is allowed from the VNet and the Azure load balancer, and all other inbound is denied. `https_inbound_source_prefixes` adds an inbound TCP 443 rule for the listed sources. |

> **Why /23 and not /24?** Azure Container Apps uses the infrastructure subnet to provision internal load balancers, envoy proxies, and platform components. A `/24` (256 addresses) does not provide enough addresses and Azure will reject the deployment with an error.

### How Subnets Are Calculated

Subnets are dynamically calculated using Terraform's `cidrsubnet()` function to avoid CIDR clashes (same pattern as the AWS deployments):

```hcl
# From main.tf — subnet_configs passed to the networking module
subnet_configs = [
  {
    newbits = 7    # cidrsubnet("10.0.0.0/16", 7, 0) = 10.0.0.0/23  (CA environment)
    netnum  = 0
    delegation = { ... Microsoft.App/environments ... }
  },
  {
    newbits = 8    # cidrsubnet("10.0.0.0/16", 8, 2) = 10.0.2.0/24  (services)
    netnum  = 2
    delegation = null
  }
]
```

The VNet address space defaults to `10.0.0.0/16`. To customize, override `vnet_address_space` in the networking module call and adjust `newbits`/`netnum` accordingly. **Subnet 0 must remain /23 or larger** and **must retain the `Microsoft.App/environments` delegation**.

## Quick Start

### 1. Configure Variables

Create `terraform.tfvars` from the example:

```hcl
# Azure Configuration
azure_subscription_id = "12345678-1234-1234-1234-123456789abc"
azure_tenant_id       = "12345678-1234-1234-1234-123456789abc"
resource_group_name   = "mtln-agent-rg"
location              = "eastus"

# Resource Naming
name = "mtln-agent"

# Matillion Configuration
matillion_cloud_region = "eu1"
account_id             = "your-matillion-account-id"
agent_id               = "your-unique-agent-id"
client_id              = "your-oauth-client-id"
client_secret          = "your-oauth-client-secret"

# Optional
container_image_url = "matillion.azurecr.io/cloud-agent:current"
tags = {
  Environment = "production"
  Project     = "mtln-agent"
}
```

### 2. Deploy Infrastructure

```bash
terraform init
terraform plan
terraform apply
```

### 3. Verify Deployment

```bash
# Check Container App status
az containerapp show \
  --name <container_app_name from output> \
  --resource-group mtln-agent-rg

# View logs
az containerapp logs show \
  --name <container_app_name from output> \
  --resource-group mtln-agent-rg
```

## Runner Metrics

The runner serves Prometheus metrics on `:9464/metrics` (OpenTelemetry, images
12.150.3 or later) and `:8080/actuator/prometheus` (deprecated), but
**this deployment doesn't expose either**. The runner container app has no
`ingress` block; the only ingress in the environment is the script runner's
internal TCP port 2222. Nothing outside the container app can scrape it.

Container Apps routes ingress to a single target port per app, so exposing
metrics is a design decision rather than a one-line change. The options:

- **Add internal ingress on 9464.** This makes the endpoint reachable from
  inside the Container Apps environment only. It needs a scraper running in
  the same environment, and gives one port, so pick the OpenTelemetry
  endpoint.
- **Send metrics with OTLP instead of scraping.** Have the runner push to a
  collector you run, with no ingress at all. The runner already pushes OTLP to
  Matillion, but its entrypoint fixes the exporters to that push plus the
  Prometheus endpoint. A customer-owned OTLP target would need a change in the
  runner image, not just configuration here.
- **Use Container Apps' built-in metrics** (CPU, memory, replicas, restarts)
  from Azure Monitor. They need no change, but don't include the runner's own
  `matillion_agent_*` metrics.

Which of these to support is tracked in DPC-58192. Runner scaling here is
fixed (`min_replicas = max_replicas`), so nothing in this deployment depends on
the metrics today. See
[Runner Metrics: Moving to the OpenTelemetry Endpoint](../../../blogs/runner-metrics-migration.md).

## Configuration Options

### Container Sizing

Pick a t-shirt size with `runner_size`. Container Apps' Consumption profile enforces a 1:2 vCPU:GiB ratio, so all sizes assume a Dedicated workload profile and the size also drives `workload_profile_type`:

| `runner_size` | vCPU | Memory | `workload_profile_type` | Notes |
|---|---|---|---|---|
| `small` *(default)* | 1 | 4 GiB | `D4` | Light/dev workloads |
| `medium` | 2 | 8 GiB | `D4` | Most production deployments |
| `large` | 4 | 16 GiB | `D4` | Whole D4 profile per replica |
| `xlarge` | 8 | 32 GiB | `D8` | Whole D8 profile per replica |

The workload profile must hold `replica_count` runner replicas, plus the script
runner replica when `enable_script_runner = true`, on at most
`workload_profile_max_count` instances. `large` and `xlarge` take a whole
instance each, so they need `workload_profile_max_count` of at least
`replica_count`, plus one when the script runner is enabled and does not fit
beside them. Plan fails when the requested vCPU is more than
`workload_profile_max_count` times the vCPU of a D- or E-series profile type.
The check does not include the platform's per-instance overhead, so a
configuration that exactly fills the instances (for example `medium` with
`replica_count = 2` on one D4) passes the check but may not schedule all
replicas. Raise `workload_profile_max_count` if a revision shows fewer running
replicas than `replica_count`. Other profile types are not checked.

```hcl
runner_size = "medium"
```

To override individual values (e.g. you want to run on E-series memory-optimized profiles), set any of `container_cpu`, `container_memory`, `workload_profile_type` and they take precedence over the size map:

```hcl
runner_size            = "small"  # ignored where overridden
workload_profile_type = "E4"
container_cpu         = "1.0"
container_memory      = "8Gi"
```

| Variable | Default | Description |
|---|---|---|
| `runner_size` | `"small"` | T-shirt size: `small` \| `medium` \| `large` \| `xlarge` |
| `container_cpu` | derived from `runner_size` | Override the per-container vCPU allocation |
| `container_memory` | derived from `runner_size` | Override the per-container memory allocation |
| `workload_profile_type` | derived from `runner_size` | Override the workload profile (D4, D8, D16, E-series) |
| `workload_profile_max_count` | `1` | Max instances in the workload profile. Must hold all replicas (runner plus script runner); see Container Sizing |
| `replica_count` | `2` | Fixed number of running replicas (no auto-scaling) |
| `container_image_url` | `matillion.azurecr.io/cloud-agent:current` | Runner container image |
| `zone_redundancy_enabled` | `true` | Zone redundancy for the environment |
| `storage_account_replication_type` | `LRS` | Storage replication. `ZRS` spreads copies across availability zones — see below |

### Storage Replication

`zone_redundancy_enabled` covers the Container App Environment, not the storage
account behind it. With the default `LRS` the account keeps a single copy in a
single zone, so a zone-redundant environment still has a single-zone storage
dependency. `ZRS` closes that gap and is the recommended setting for new
deployments:

```hcl
zone_redundancy_enabled          = true
storage_account_replication_type = "ZRS"
```

The default remains `LRS` so existing deployments plan clean rather than having
their storage changed by an unrelated apply.

**On an account that already holds data this is an Azure conversion, not a
Terraform edit.** Use Azure's customer-initiated conversion or a manual
migration, then update the Terraform value so state matches reality. Do not let
a `terraform apply` be the first thing that attempts it.

### Key Vault Name

The default Key Vault name is `name`, `-kv-` and the 6-character salt, cut at 24
characters, the Azure limit for a vault name. A `name` longer than 14 characters
loses salt characters. With `enable_script_runner = true`, `name` is limited to
11 characters, so the vault keeps the full salt and the rows from 15 characters
on apply only with the script runner off:

| `name` length | Salt characters kept |
|---|---|
| 14 or fewer | 6 |
| 15 to 19 | 5 to 1 |
| 20 | none; the vault name ends in `-` and the plan fails |
| 21 to 23 | none; a 23-character `name` gives a vault name ending in `-` and the plan fails |
| 24 or more | none; the vault name is the first 24 characters of `name` |

Vault names are global across Azure, and a deleted vault keeps its name for the
soft-delete retention period (7 days in this deployment). Fewer salt characters
make a collision with another deployment, or with a vault destroyed in the last
7 days, more likely.

A `name` of 15 characters or more gives a warning at plan (`Check block
assertion failed`). A derived vault name that ends in `-` fails the plan: a
`name` of 20 or 23 characters, or a longer one whose 24th character is `-`.
Both checks read only `name` and assume the 6-character alphanumeric salt that
this root generates, so they run at plan on a new deployment, before the salt
exists.

Setting `resource_names["key_vault"]` on `modules/azure/container-apps` replaces
the default name and skips both checks. This root does not expose that on its
own: `naming_overrides` is ignored unless `naming_tokens` is set, and setting
`naming_tokens` names every resource from the naming convention, which renames
every resource of an existing deployment.

With the default resource names, a `name` of 22 characters or more already fails
the plan on the Container App name, which is `name`, `-app-` and the salt and is
limited to 32 characters.

Effect on existing deployments:

- `name` of 14 characters or fewer: no change.
- `name` of 15 to 19 characters: a warning at every plan. The vault name and the
  planned changes are unchanged, and the plan exits 0. Do not shorten `name` to
  clear the warning: changing `name` changes every default resource name,
  including the vault's, and replaces those resources. Accept the warning.
- `name` of 20 characters: the plan fails. Azure rejects a vault name ending in
  `-`, so no existing deployment can use this name with the default vault name.
- `name` of 21 characters: a warning, and the vault name has no salt.
- `name` of 22 characters or more (only with `resource_names["container_app"]` set): a
  warning, or a failed plan for 23 characters and for a 24th character of `-`.
- Terraform 1.0 to 1.4: `terraform init` fails on the version constraint. This
  deployment now needs Terraform 1.5 or later for the `check` block.

### Networking

| Variable | Default | Description |
|---|---|---|
| `enable_nat_gateway` | `false` | Enable NAT Gateway for controlled outbound egress |
| `nat_gateway_idle_timeout` | `10` | NAT Gateway idle timeout in minutes (4-120) |
| `https_inbound_source_prefixes` | `[]` | Sources allowed inbound on TCP 443 through the subnet NSG. Empty adds no rule; `["*"]` allows any source |
| `key_vault_allowed_ip_ranges` | `[]` | Public IPv4 addresses or CIDRs allowed through the Key Vault firewall. See [Adding secrets to the Key Vault](#adding-secrets-to-the-key-vault) |

### Disabling Python Script and Bash Script

Set `disable_script_execution = true` to stop the Python Script and Bash Script
components running on the runner. The Container App then sets
`SCRIPT_OOM_PROTECTION_ENABLED=false` and points `MTLN_PYTHON_3_COMMAND` and
`MTLN_BASH_COMMAND` at paths that do not exist, so both components fail at Run
with `Cannot run program "/python-script-disabled-on-this-runner"...`. Script
Pushdown (`enable_script_runner`) still works. To stop scripts running anywhere, also
set `enable_script_runner = false`.

```hcl
disable_script_execution = true
```

Pipelines still pass Validate, the setting is per runner, and it relies on
internal runner settings, so re-check it after runner upgrades. See
[Disabling Python Script and Bash Script](../../../README.md#disabling-python-script-and-bash-script).

### Environment-Specific Examples

**Development:**
```hcl
runner_size              = "small"   # 1 vCPU / 4 GiB on D4
replica_count           = 1
zone_redundancy_enabled = false
```

**Production:**
```hcl
runner_size                = "large"   # 4 vCPU / 16 GiB on D4
replica_count              = 2
workload_profile_max_count = 2         # one D4 instance per large replica
zone_redundancy_enabled    = true
enable_nat_gateway         = true
```

## Security

### Resources Created Automatically

- **User Assigned Managed Identity** with roles:
  - `AcrPull` on the registry named by `container_acr_id`, only when it is set - pull the runner image from a private registry
  - `Storage Account Contributor` - manage storage
  - `Storage Blob Data Contributor` - read/write blobs
  - `Key Vault Secrets Officer` - manage secrets
  - `Key Vault Secrets User` - read secrets
  - `Reader` on Key Vault - metadata access
- **Key Vault** - RBAC-enabled, network-restricted to VNet subnets, 7-day soft delete
- **Storage Account** - Standard LRS, no public access
- **Key Vault Administrator** role assigned to the identity running Terraform, or to the principals in `key_vault_administrator_principal_ids` (see below)

### Key Vault administrators

| Variable | Default | Description |
|---|---|---|
| `key_vault_administrator_principal_ids` | `null` | Entra object IDs (GUIDs) of the users, groups or service principals granted Key Vault Administrator. Null grants the identity running Terraform |

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

Each entry must be an object ID (GUID); the plan fails on anything else, such
as a user principal name. Values must be known at plan time; IDs of principals
created in the same apply fail with Terraform's `for_each` error.

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

### Role assignment principal type

The module sets `principal_type = "ServicePrincipal"` on the role assignments
for the Container App managed identity and, when `enable_script_runner = true`,
the script runner identity, so Azure does not look the principal up in Entra ID
before assigning the role. The deployer's Key Vault Administrator assignment is
not changed, because the deployer can be a user or a service principal.

On existing deployments `terraform plan` is expected to show no change for
these assignments, because Azure records `principalType` as `ServicePrincipal`
for managed identities and the provider reads it into state. This was measured
on the AKS module on 2026-11-13 (seven assignments: the plan of the changed
configuration showed no changes, and the apply was 0 added, 0 changed,
0 destroyed). It has not been measured on Container Apps.

Role assignments that Azure stored with an empty `principalType` were not
tested. For such a deployment, run `terraform plan` before applying and check
the action on each role assignment. Do not apply a plan that replaces a role
assignment without reviewing it.

### Network Security

- Key Vault network ACLs default deny, with the VNet subnets, Azure trusted services and any `key_vault_allowed_ip_ranges` allowed
- NSG on all subnets uses the Azure default inbound rules (VNet and Azure load balancer allowed, everything else denied), plus TCP 443 from `https_inbound_source_prefixes` when set

### Adding secrets to the Key Vault

The runner reads secrets from the vault named in its `DEFAULT_KEYVAULT`
environment variable, which is the vault this deployment creates. Get its name with:

```bash
terraform output -raw key_vault_name
```

The vault's Key Vault Administrators (by default, the identity that ran
`terraform apply`) can manage secrets, but the vault firewall denies requests
from outside the deployment's subnets. From a laptop,
`az keyvault secret set` and `az keyvault secret list` fail with:

```
(Forbidden) Client address is not authorized and caller is not a trusted service.
```

Use one of the following.

**Allow your egress IP.** Find your public IPv4 address:

```bash
curl -4 -s https://ifconfig.me
```

Set it in `terraform.tfvars` and run `terraform apply`. This is an in-place
update of the vault; the vault is not replaced.

```hcl
key_vault_allowed_ip_ranges = ["203.0.113.10"]
```

Give a single address without a prefix. Key Vault does not accept `/31` or `/32`
rules, and the variable rejects them, along with prefixes shorter than `/8` and
private (RFC 1918) ranges.

The rule can take up to a minute to take effect. Then add and check the secrets:

```bash
az keyvault secret set --vault-name <vault> --name <name> --value <value>
az keyvault secret list --vault-name <vault> -o table
```

Remove the entry and apply again when you no longer need access. Only public
addresses work: requests from inside Azure on a subnet with the
`Microsoft.KeyVault` service endpoint are matched by the subnet rule, not by an
IP rule.

**Run `az` inside the VNet.** Run the commands from a host on a subnet in
`subnet_ids`. Use the services subnet (index 1, `10.0.2.0/24` with the default
address space). The Container Apps subnet (index 0) is delegated to
`Microsoft.App/environments` and cannot hold a VM. The NSG on these subnets
allows no inbound traffic from outside the VNet by default (and only TCP 443
from `https_inbound_source_prefixes` when set), so you cannot SSH or RDP to the
VM from outside the VNet without changing it. Run the commands with
`az vm run-command invoke --command-id RunShellScript --scripts "..."`, connect
through Azure Bastion (which needs its own `AzureBastionSubnet`), or add a
temporary NSG rule for your address and remove it afterwards.

**Use a private endpoint.** Create a private endpoint for the vault, with a
private DNS zone `privatelink.vaultcore.azure.net` linked to the network you
connect from. This module does not create one.

Do not add rules with `az keyvault network-rule add` or the Azure portal. The
module manages the vault's network rules in full, so the next `terraform apply`
removes any rule it does not know about. Use `key_vault_allowed_ip_ranges`
instead.

## Monitoring

### Log Analytics Queries

```kusto
// Container logs
ContainerAppConsoleLogs_CL
| where ContainerAppName_s contains "matillion"
| order by TimeGenerated desc

// Resource usage warnings
ContainerAppSystemLogs_CL
| where EventType_s == "Warning"
```

## Limitations

- **No Auto-scaling**: Container Apps in this deployment uses a fixed replica count. Auto-scaling is a Kubernetes/AKS feature.
- **Single Container**: No sidecar support (unlike AKS). Metrics sidecar not available.
- **Subnet Restrictions**: Infrastructure subnet must be /23 or larger, delegated to `Microsoft.App/environments`, and dedicated (not shared).

For auto-scaling, sidecar support, and advanced networking, consider the [AKS deployment](../aks/) instead.

## Cleanup

```bash
terraform destroy
```

## Comparison with AKS Deployment

| Feature | Container Apps | AKS |
|---|---|---|
| **Management** | Fully Managed | Managed Control Plane |
| **Scaling** | Fixed replica count | Auto-scaling (HPA) |
| **Networking** | Dedicated /23 subnet required | /24 subnets sufficient |
| **Sidecar Support** | No | Yes |
| **Cost** | Pay-per-use | Node-based |
| **Complexity** | Low | High |
| **Prerequisites** | Created automatically | Created automatically |
