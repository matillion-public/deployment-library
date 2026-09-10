# Azure resource naming

Builds Azure resource names from your own naming convention, and hands them to the
deployment modules. Nothing here creates infrastructure — it is computation and
validation only.

The modules generate perfectly good names on their own. Reach for this when an
organisation has a naming standard that resource names have to satisfy, which is
usually the point at which a platform team is asked to prove every resource follows
it.

## Quick start

```hcl
module "naming" {
  source = "../../modules/azure/naming"

  tokens = {
    bu        = "ng"
    env       = "p"
    env_short = "pd"     # the short form, for length-capped dashless names
    region    = "eus2"
    purpose   = "runner"
    instance  = "01"
  }
}

module "networking" {
  source         = "../../modules/azure/networking"
  resource_names = module.naming.names
  # ...
}
```

That produces `ng-p-eus2-runner-vnet-01`, `ng-p-eus2-runner-natgw-01`, and
`ngpdeus2runnerst01` for the storage account.

## How a name is built

A name is a format string with the tokens substituted in:

| Token | From |
|---|---|
| `{bu}` | `tokens.bu` |
| `{env}` | `tokens.env` |
| `{envs}` | `tokens.env_short` |
| `{region}` | `tokens.region` |
| `{purpose}` | `tokens.purpose` |
| `{instance}` | `tokens.instance` |
| `{type}` | the resource abbreviation, from `resource_specs` |

Two forms ship by default:

```
dashed     {bu}-{env}-{region}-{purpose}-{type}-{instance}
dashless   {bu}{envs}{region}{purpose}{type}{instance}
```

`dashless` exists for the resources Azure requires to be short and separator-free —
storage accounts and container registries. That is also why there are two environment
tokens: conventions typically use a longer form in dashed names and a shorter one
where 24 characters is the ceiling.

**Empty tokens drop out cleanly.** A convention with no purpose segment gives
`ng-p-eus2-vnet`, not `ng-p-eus2--vnet-`.

Override a form to change segment order or add a prefix:

```hcl
formats = { dashed = "lz{bu}-{env}-{region}-{purpose}-{type}-{instance}" }
```

## Resource keys

| Key | Abbreviation | Form | Purpose | Azure limit |
|---|---|---|---|---|
| `vnet` | `vnet` | dashed | | 64 |
| `nsg` | `nsg` | dashed | | 80 |
| `nat_gateway` | `natgw` | dashed | | 80 |
| `nat_public_ip` | `pip` | dashed | | 80 |
| `aks_cluster` | `aks` | dashed | | 63 |
| `log_workspace` | `log` | dashed | | 63 |
| `key_vault` | `kv` | dashed | | 24 |
| `container_app` | `ca` | dashed | | 32 |
| `container_app_environment` | `cae` | dashed | | 60 |
| `servicebus_namespace` | `sbns` | dashed | | 50 |
| `script_runner_app` | `ca` | dashed | `scriptrunner` | 32 |
| `state_resource_group` | `rg` | dashed | `tfstate` | 90 |
| `aks_identity` | `id` | dashed | `aks` | 128 |
| `runner_identity` | `id` | dashed | `runner` | 128 |
| `container_app_identity` | `id` | dashed | `ca` | 128 |
| `queue_adapter_identity` | `id` | dashed | `queueadapter` | 128 |
| `script_runner_identity` | `id` | dashed | `scriptrunner` | 128 |
| `tenant_runner_identity` | `id` | dashed | `tenantrunner` | 128 |
| `runner_federated_credential` | `fic` | dashed | `runner` | 120 |
| `script_runner_federated_credential` | `fic` | dashed | `scriptrunner` | 120 |
| `tenant_runner_federated_credential` | `fic` | dashed | `tenantrunner` | 120 |
| `tenant_script_runner_federated_credential` | `fic` | dashed | `tenantscriptrunner` | 120 |
| `storage_account` | `st` | dashless | | 24 |
| `queue_storage_account` | `st` | dashless | `queue` | 24 |
| `trigger_storage_account` | `st` | dashless | `trigger` | 24 |
| `state_storage_account` | `st` | dashless | `tfstate` | 24 |
| `state_container` | `stct` | dashed | `tfstate` | 63 |

### Why some keys carry their own purpose

Conventions abbreviate by resource *type*, so every managed identity is `id` and every
federated credential is `fic`. Left alone, six identities would generate the same
name, and the AKS module wires two of them — the collision surfaces as a duplicate
resource name on apply.

Each identity and credential therefore has **its own key, one per consuming
resource**. That matters because the uniqueness check compares key against key: it
cannot see a single key being read by two different resources, so
`modules/azure/runner-identity` (which is one identity per runner deployment, and can
be composed alongside `aks`) uses the `tenant_*` keys rather than sharing the runner's.

`storage_account`, `key_vault` and `log_workspace` are deliberately shared between the
`aks` and `container-apps` modules — those are alternative compute backends deployed
from separate root configs, so the same logical resource is named once.

A key with a `purpose` in the table above substitutes that instead of
`tokens.purpose`, so they come out distinct. Override it if your standard says
otherwise:

```hcl
resource_specs = {
  runner_identity = { type = "id", form = "dashed", max_length = 128, purpose = "runner-workload" }
}
```

Any convention that still produces two identical names **fails the plan**, naming both
keys.

Change an abbreviation, or add a resource this table does not cover:

```hcl
resource_specs = {
  vnet         = { type = "vn" }                                   # keeps form/limit
  my_own_thing = { type = "mot", form = "dashed", max_length = 80 } # new key, so give it all three
}
```

`resource_specs` is merged into the built-in table **per attribute**, so naming one
field leaves the rest alone — `{ type = "vn" }` keeps `vnet`'s 64-character limit
rather than resetting it. A key the table does not already contain needs its
`max_length` set, since there is no built-in limit to inherit.

## When the convention does not fit

Not every standard is expressible as a template — some are irregular, and an existing
platform may already have names that cannot change. Set them outright:

```hcl
overrides = { vnet = "an-existing-name-we-cannot-change" }
```

Overrides win over anything generated, and are still validated.

## Subnets are named individually

Subnets are not in the `names` map. Each one carries a different purpose — nodes,
pods, private endpoints, egress — so a single template cannot name them all. Name
them on the subnet itself:

```hcl
subnet_configs = [
  { name = "lzng-p-eus2-nodes-snet-01", newbits = 8, netnum = 1 },
  { name = "lzng-p-eus2-pods-snet-02",  newbits = 6, netnum = 4 },
]
```

Leave `name` unset and the existing generated name is used.

## Validation

Names are checked at **plan** time, not apply. Three things are enforced:

- **Length**, against the Azure limit for that resource type. A convention producing a
  26-character Key Vault name fails, naming the key and the limit it broke.
- **Charset**. The dashless form must be lowercase alphanumeric with no separators;
  nothing may start or end with a separator. Lowercase and separator-free are separate
  constraints — a storage container is lowercase but does allow hyphens.
- **Uniqueness**. Two keys resolving to the same name fails the plan.

Names are **not truncated to fit**. That is deliberate: silently cutting a name to
`max_length` drops the trailing `{type}` and `{instance}` segments, so two deployments
differing only by instance number collapse onto the same name. For a globally unique
type like a storage account the second one then fails at apply, in a separate state
where the uniqueness check cannot see it. A name that does not fit is a convention
error, so it fails the plan — shorten a token, use `env_short`, or set that key in
`overrides`.

## This applies to Azure resources only

Kubernetes names — the namespace, the ServiceAccounts — are deliberately **not**
covered, and should not be renamed to match an Azure convention. The workload identity
federated credential subject references the namespace and ServiceAccount exactly; if
they no longer match what the Helm chart deploys, AAD token exchange fails and the
runner cannot read Key Vault. The symptom is an authentication error at runtime, well
after a clean apply.

## Compatibility

`resource_names` defaults to an empty map, and every module falls back to the name it
generates today. An existing deployment that does not set it plans clean, with no
changes.

Adding naming to a **deployed** platform renames live resources, which for most Azure
resource types means destroy and recreate. Check the plan.

## Tests

```sh
cd modules/azure/naming && terraform test
```
