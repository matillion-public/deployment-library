# Runner in an existing AKS cluster

Puts one Matillion runner into an AKS cluster you already run, next to any other runners there. The cluster itself is left alone: Terraform creates nothing in it. Each runner gets these, named after the runner:

- **Namespace and service accounts:** the namespace `<name>`, with service accounts `<name>-sa` and `<name>-script-runner-sa`. The runner chart creates all three when you install it with Helm; Terraform only binds identities to those names.
- **Managed identities:** one for the runner and one for the script runner, each federated to its own service account name and nothing else. The script runner runs code people write, so its identity has blob access to the runner's storage accounts, and no Key Vault or storage account keys.
- **Key Vault:** a vault of its own, which only the runner can read and write. See [Secrets](#secrets).
- **Storage:** access to the storage accounts you list in `storage_account_ids`, and no others.

Each runner in a cluster needs its own name, even when their resource groups differ. An identity trusts `system:serviceaccount:<name>:<name>-sa`, which is the same subject for any two runners with the same name. A second one would use the first one's identity, and so read its secrets. Names also can't be `default`, start with `kube-`, or end in `-scripts`.

To create a new cluster for the runner instead, use [`../aks`](../aks/).

## Before you start

- **The cluster needs its OIDC issuer and workload identity.** Turn both on once per cluster: `az aks update --resource-group <group> --name <cluster> --enable-oidc-issuer --enable-workload-identity`. Without the OIDC issuer the plan stops at the cluster lookup. Terraform can't see whether workload identity is on, so check it yourself (`az aks show --resource-group <group> --name <cluster> --query securityProfile.workloadIdentity.enabled`). Without it everything applies cleanly, but the webhook that hands pods their token never runs. The runner then fails at start-up with an Azure identity or token error, such as IMDS "Identity not found". The fix is `az aks update --enable-workload-identity`, then restarting the runner's pods.
- **You need to assign roles.** The apply creates role assignments, so whoever runs it needs Owner, User Access Administrator or Role Based Access Control Administrator on the resource group and on each storage account in `storage_account_ids`.
- **The runner needs its own Matillion registration.** Register the runner in Matillion first, so it has its own client ID and secret.

## Deploy

```bash
cp terraform.tfvars.example terraform.tfvars   # set name, azure_subscription_id, cluster_name and cluster_resource_group_name
terraform init
terraform apply
```

Then install the chart into the runner's namespace with the outputs, as in [Shared Multi-Tenant Platform](../../helm/README.md#shared-multi-tenant-platform):

```bash
helm install "$(terraform output -raw namespace)" ../../helm/runner \
  --namespace "$(terraform output -raw namespace)" --create-namespace \
  -f ../../helm/runner/values-azure.yaml \
  -f my-runner-values.yaml \
  --set azure.subscriptionId="$(terraform output -raw subscription_id)" \
  --set azure.workloadIdentity.clientId="$(terraform output -raw workload_identity_client_id)" \
  --set dpcAgent.dpcAgent.env.defaultKeyvault="$(terraform output -raw key_vault_name)" \
  --set serviceAccount.name="$(terraform output -raw service_account_name)" \
  --set scriptRunner.serviceAccount.name="$(terraform output -raw script_runner_service_account_name)" \
  --set scriptRunner.serviceAccount.clientId="$(terraform output -raw script_runner_client_id)"
```

- `values-azure.yaml` sets `cloudProvider: azure` and turns on workload identity. Without it the chart adds no identity annotation, and the runner gets no Azure credentials. It also sets placeholder values, such as `azure.subscriptionId`, which the `--set` lines replace.
- `scriptRunner.enabled` defaults to `false`. To run the script runner, set it to `true` in the runner's values file. `scriptRunner.serviceAccount.clientId` is then required, and the `--set` line above supplies it.
- `my-runner-values.yaml` holds the runner's own credentials and IDs, as in [`values-tenant-example.yaml`](../../helm/runner/values-tenant-example.yaml).
- `azure.subscriptionId` is where the runner looks for Key Vaults and storage accounts. Storage accounts in another subscription don't appear in the runner's storage account picker, so keep the runner's accounts in this one.

If the cluster's Prometheus scales runners, add the namespace to its `scrapeNamespaces` and `networkPolicy.additionalScrapeNamespaces`, and widen its pod regexes and selectors, because this release isn't named `matillion-runner`. Otherwise the runner never scales beyond its minimum, and nothing logs why. The helm README's "Wiring the shared Prometheus" section shows how.

Role assignments can take a few minutes to reach Key Vault and Storage. A runner started straight after the apply may get 403 errors at first; they clear on their own.

## Secrets

Azure RBAC can't limit a role to secrets whose names start with a prefix, as AWS can, so each runner gets a vault of its own and the vault is the boundary. The chart points the runner at it through `dpcAgent.dpcAgent.env.defaultKeyvault`. That covers secrets created from Matillion, and secrets holding OAuth tokens the runner refreshes. Reading another runner's vault is refused with a 403 naming the vault.

- **Name:** up to 17 characters of the runner's name, a hyphen and 6 random characters, such as `finance-a1b2c3`. Key Vault names are unique across Azure and limited to 24 characters, so the suffix keeps two deployments called `finance` apart.
- **The runner's role:** Key Vault Secrets Officer on its vault, and Reader so the vault appears in the runner's vault picker. The runner reads, creates, updates and lists secrets. No built-in role allows writing a secret without also allowing deleting it, so it can delete too.
- **Public network access is on.** The vault has no network rules, so it accepts requests from any network, and Entra ID and RBAC are the only gate. To close it, add a private endpoint or firewall rules in the cluster's network; this root doesn't own that network.
- **Deleted secrets are recoverable.** The vault has purge protection and 7 days' soft delete, so a deleted secret can be recovered for 7 days and can't be purged sooner. The same goes for the vault itself after `terraform destroy`, and its name stays taken until then.
- **Purge protection is permanent.** Azure can't turn it off once it is on, for this vault or any other.
- **Whoever runs Terraform gets no role on the vault.** Nothing here reads or writes a secret. To look at a runner's secrets, grant yourself Key Vault Secrets User on that vault separately.

## Compared to `../aks`

- **Key Vault:** `../aks` makes one vault, and every runner using its identity can read every secret in it. Here each runner has its own.
- **Script runner:** `../aks` gives the script runner the runner's identity, Key Vault included. Here it has its own identity, without Key Vault.
- **Storage:** `../aks` creates a staging account and grants that. This root creates none and, by default, grants none: list the business unit's own accounts in `storage_account_ids`. Both identities get Storage Blob Data Contributor on each. The runner also gets Reader and Data Access, because it signs Snowflake and Databricks staging SAS tokens with the account's key; that key covers the whole account, so list only accounts the runner is meant to use. Set `grant_storage_account_keys = false` to give blob access only; Snowflake and Databricks loads from Azure staging, and the storage account picker, then stop working.
- **Subscription:** `../aks` grants the runner Reader on the whole subscription by default (`grant_runner_subscription_reader`). This root grants none: on a shared subscription it would show the runner every other business unit's resources.
