# core/account

Provider-agnostic root configuration for a composer-driven agent deployment.
Declares the **target account / subscription / project** and **region**, plus the
`deployment_name` and `tags` that every other composer module inherits.

This module provisions **no cloud resources** — it is a configuration contract.
Downstream modules (`core/compute-*`, `core/auth-*`, `core/networking-*`) read its
outputs so the account/region are defined once.

## Inputs
| Name | Description | Default |
|------|-------------|---------|
| `region` | Target cloud region | *(required)* |
| `cloud` | `aws` \| `azure` \| `gcp` | `aws` |
| `aws_account_id` / `azure_subscription_id` / `gcp_project_id` | Target account for the selected cloud | `""` |
| `deployment_name` | Resource name prefix | `matillion-agent` |
| `tags` | Common tags/labels | `{}` |

## Outputs
`cloud`, `region`, `target_account`, `deployment_name`, `tags`.
