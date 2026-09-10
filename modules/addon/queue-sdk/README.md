# addon/queue-sdk (AWS + Azure)

**No-op module by design.** In SDK trigger mode the agent polls the Matillion
control plane directly over the SDK — there is **no** queue, adapter, or other
cloud infrastructure to provision. This module provisions no resources; it exists
so the composer's declared path resolves and so the polling configuration has a
single typed home.

## Inputs
| Name | Description | Default |
|------|-------------|---------|
| `poll_interval_seconds` | SDK poll interval | `10` |
| `max_concurrent_runs` | Max concurrent runs | `4` |

## Outputs
`poll_interval_seconds`, `max_concurrent_runs`.
