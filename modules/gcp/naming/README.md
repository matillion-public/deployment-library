# GCP resource naming

Builds GCP resource names from your own naming convention, and hands them to the
deployment modules. Nothing here creates infrastructure — it is computation and
validation only.

The modules generate perfectly good names on their own. Reach for this when an
organisation has a naming standard that resource names have to satisfy, which is
usually the point at which a platform team is asked to prove every resource follows
it.

This is the GCP counterpart to `modules/azure/naming` and `modules/aws/naming`. The
mechanism is the same. GCP has the fewest name sites of the three and the tightest
rules — read the two constraints below before choosing a convention.

## Quick start

```hcl
module "naming" {
  source = "../../modules/gcp/naming"

  tokens = {
    bu        = "ng"
    env       = "p"
    env_short = "pd"     # the short form, for the 30-character service accounts
    region    = "euw1"
    purpose   = "runner"
    instance  = "01"
  }
}

module "networking" {
  source         = "../../modules/gcp/networking"
  resource_names = module.naming.names
  # ...
}
```

That produces `ng-p-euw1-runner-vpc-01`, `ng-p-euw1-runner-gke-01`,
`ng-p-euw1-runner-sa-01`, and `ng_p_euw1_runner_secretcreator_01` for the custom role.

Tokens must be **lowercase and start with a letter**. Most GCP resource types are
RFC1035, and an uppercase or digit-leading token fails the plan.

## Two constraints to know before choosing a convention

### Service accounts cap at 30 characters

`account_id` allows 6–30 characters. There are three of them —
`node_service_account`, `runner_workload_service_account` and
`runner_service_account` — and a six-segment convention does not reliably fit. The
short convention in the example above lands at 20–24 characters; a longer business
unit or region token will not.

A name longer than 30 characters is **not truncated** — truncating would drop the
trailing `{type}` and `{instance}` segments and collapse two distinct service accounts
onto one identity, which is worse than failing. It fails the plan instead. If your
convention does not fit, set these three explicitly:

```hcl
overrides = {
  node_service_account            = "ng-p-node-sa-01"
  runner_workload_service_account = "ng-p-rwl-sa-01"
  runner_service_account          = "ng-p-runner-sa-01"
}
```

This is worth settling during convention review rather than discovering at plan time.

### Custom role ids reject hyphens

`google_project_iam_custom_role.role_id` allows letters, digits, underscores and
dots — no hyphens. `runner_secret_creator_role` therefore uses the `underscore`
form, generating `ng_p_euw1_runner_secretcreator_01`.

The name is generated in that form rather than having its hyphens replaced
afterwards, so the string that is validated for length, charset and uniqueness is
the string that is actually used.

## How a name is built

A name is a format string with the tokens substituted in:

| Token | From |
|---|---|
| `{bu}` | `tokens.bu` |
| `{env}` | `tokens.env` |
| `{envs}` | `tokens.env_short` |
| `{region}` | `tokens.region` |
| `{purpose}` | the spec's own `purpose`, else `tokens.purpose` |
| `{type}` | the spec's `type` — the resource abbreviation |
| `{instance}` | `tokens.instance` |

Two forms ship:

| Form | Format | Used by |
|---|---|---|
| `dashed` | `{bu}-{env}-{region}-{purpose}-{type}-{instance}` | everything RFC1035 |
| `underscore` | `{bu}_{env}_{region}_{purpose}_{type}_{instance}` | custom role ids |

Any token left empty drops out without leaving a doubled or trailing separator
behind. The `underscore` form collapses to an underscore rather than a hyphen, since
a hyphen would be invalid for the only key that uses it.

## Resource keys

16 keys, grouped by the module that consumes them:

| Module | Keys |
|---|---|
| `gcp/networking` | `vpc`, `subnet`, `pod_secondary_range`, `services_secondary_range`, `nat_router`, `nat_ip`, `cloud_nat` |
| `gcp/gke` | `gke_cluster`, `node_pool`, `gke_node_network_tag`, `node_service_account`, `runner_workload_service_account`, `staging_bucket`, `runner_secret`, `runner_secret_creator_role` |
| `gcp/runner-identity` | `runner_service_account` |

### Why some keys carry their own purpose

Conventions abbreviate the resource type, so all three service accounts are `sa`.
Without something to tell them apart they would generate the same name and collide
on apply, so each carries a distinguishing `purpose` — `node`, `runnerwl` and
`runner` — overridable per key in `resource_specs`.

### Subnet and secondary range names

The subnet and its two secondary ranges take their base name from the map and keep
the existing `-<index>` suffix, since one template cannot name N of them. The GKE
cluster reads the secondary range names back through the networking module's
outputs, so naming them here keeps both sides in step automatically.

## Character sets are per resource type

| `charset` | Pattern | Used by |
|---|---|---|
| `rfc1035` | lowercase, starts with a letter, ends alphanumeric | the default — most resources |
| `gcs` | lowercase, `.` `_` `-`, starts and ends alphanumeric | storage buckets |
| `secret` | letters, digits, `_` `-` | Secret Manager secret ids |
| `role` | starts with a letter, then letters, digits, `_` `.` | custom role ids |

## Validation

Names are checked at **plan** time, not apply. Four things are enforced:

- **Maximum length**, against the GCP limit for that resource type. Service accounts
  at 30 and clusters and node pools at 40 are the tight ones. Over-length fails the
  plan rather than being truncated.
- **Minimum length.** GCP enforces minimums too — 6 for service accounts, 3 for
  buckets and custom roles. Azure has no equivalent, so neither did the module this
  was adapted from.
- **Character set**, per resource type, as above. This is where a convention that
  starts with a digit or contains an uppercase letter fails, with the RFC1035 rule
  quoted in the error.
- **Uniqueness.** Two keys resolving to the same name fails the plan — most likely
  where two service accounts are given the same `purpose`.

Each failure names the offending key, its value and the rule it broke.

### Overriding part of a spec

`resource_specs` is merged into the built-in table **per attribute**, so naming one
field leaves the rest alone:

```hcl
resource_specs = {
  runner_service_account     = { type = "svcacct" }   # keeps the 30-char cap
  runner_secret_creator_role = { type = "seccreate" } # keeps the underscore form
}
```

A key the table does not already contain needs `type`, `charset` and `max_length` set
explicitly, since there is no built-in spec to inherit from.

## When the convention does not fit

Not every standard is expressible as a template — some are irregular, and an existing
platform may already have names that cannot change. Set them outright:

```hcl
overrides = { gke_cluster = "an-existing-name-we-cannot-change" }
```

Overrides win over anything generated, and are still validated.

## This applies to GCP resources only

Kubernetes names — the namespace, the ServiceAccounts — are deliberately **not**
covered, and should not be renamed to match a GCP convention. GKE Workload Identity
binds the Kubernetes service account name into the IAM policy member string
(`serviceAccount:<project>.svc.id.goog[<namespace>/<ksa>]`); if it no longer matches
what the Helm chart deploys, token exchange fails and the runner cannot reach GCP
APIs. The symptom is an authentication error at runtime, well after a clean apply.

`gke_node_network_tag` is a network tag rather than a resource name, and is included
because a convention usually covers tags too. Firewall rules target it — including
any the customer maintains outside this repo — so renaming it means updating those
in step.

## Compatibility

`resource_names` defaults to an empty map, and every module falls back to the name it
generates today. An existing deployment that does not set it plans clean, with no
changes.

Adding naming to a **deployed** platform renames live resources, which for most GCP
resource types means destroy and recreate — and for service accounts means the IAM
bindings that reference them are rebuilt too. Check the plan.

## Tests

```sh
cd modules/gcp/naming && terraform test
```

16 tests, covering the dashed convention, the hyphen-free role id and a hyphenated
one failing, a digit-leading and an uppercase convention failing RFC1035, lowercase
buckets, empty tokens collapsing per form without dangling separators, service
accounts fitting inside 30 characters, an over-long convention failing that cap, a
name under the GCP minimum failing, overrides winning, custom formats, a partial
`resource_specs` override keeping the built-in attributes (and still respecting the
30-character cap), and the default convention generating no duplicates.
