# core/networking-vpc (AWS **and** GCP — shared composer path)

Both the AWS and GCP composer contracts declare their networking module at the
**same** `modules/core/networking-vpc` path. Rather than fork the path (which
would break one of the two contracts), this single module serves both providers
via a `cloud` selector (`aws` | `gcp`) with count-gated resources — the inactive
provider's resources resolve to zero.

The module references an existing VPC/network + subnets (bring-your-own) and
emits the least-privilege permission set the composer contract declares:

| Cloud | Inputs | Deployer permissions |
|-------|--------|----------------------|
| `aws` | `vpc_id`, `subnet_ids` | `ec2:DescribeVpcs`, `ec2:DescribeSubnets`, `servicediscovery:CreateService` |
| `gcp` | `project_id`, `network`, `subnetwork` | `compute.networks.get`, `compute.subnetworks.get` |

> Azure uses the separate [`core/networking-vnet`](../networking-vnet) path.

## Outputs
`network_id`, `subnet_ids` (cloud-neutral), plus `deployer_policy_arn` (AWS) /
`deployer_role_id` (GCP).
