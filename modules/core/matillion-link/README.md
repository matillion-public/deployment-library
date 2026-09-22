# core/matillion-link

Links the deployed agent to Matillion Cloud. Provider-agnostic configuration
contract holding the account ID, control-plane region, and the sensitive OAuth
`client_secret`. Provisions no cloud resources; the `core/auth-*` modules place
the secret in the provider-native secret store and the `core/compute-*` modules
inject the account/region into the agent runtime.

## Inputs
| Name | Description | Default |
|------|-------------|---------|
| `account_id` | Matillion account ID | *(required)* |
| `region` | Matillion control-plane region | `eu1` |
| `client_secret` | OAuth client secret (**sensitive**) | *(required)* |
| `agent_id` | Matillion agent ID | `""` |

## Outputs
`account_id`, `region`, `agent_id`, `client_secret` (sensitive).
