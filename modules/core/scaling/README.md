# core/scaling

Agent replica bounds / autoscaling policy. Provider-agnostic configuration
contract — provisions no cloud resources. The `core/compute-*` modules read
these outputs to set replica counts and to decide whether to attach a
provider-native autoscaler.

## Inputs
| Name | Description | Default |
|------|-------------|---------|
| `min_agents` | Minimum replicas | `1` |
| `max_agents` | Maximum replicas | `5` |
| `autoscale` | Enable autoscaling between min/max | `false` |

`max_agents >= min_agents` is enforced at plan time.

## Outputs
`min_agents`, `max_agents`, `autoscale`, `desired_agents`.
