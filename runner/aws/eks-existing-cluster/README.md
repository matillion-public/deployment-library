# Runner in an existing EKS cluster

Puts one Matillion runner into an EKS cluster you already run, next to any other runners there. The cluster itself is left alone. Each runner gets these, named after the runner:

- **Names for its namespace and service accounts:** `<name>`, `<name>-sa` and `<name>-script-runner-sa`. Helm creates them when you install the chart below; this sets up the AWS side that trusts them. If you set `serviceAccount.create=false`, create them yourself with exactly these names.
- **IAM roles:** one for the runner and one for the script runner, each trusted by its own service account and nothing else (`StringEquals`, not a wildcard). The script runner runs code people write, so its role has the runner's buckets and no secrets.
- **Secrets:** the runner can read, create and update only secrets named `matillion/<name>/...`.
- **S3:** access to the buckets you list in `s3_bucket_arns`.
- **Fargate (optional):** a Fargate profile for the namespace, named `runner-<name>`, when the cluster runs pods on Fargate.

To create a new cluster for a runner instead, use [`../eks`](../eks/).

Runner names must be unique in the cluster. They can't be `default`, start with `kube-`, or end in `-scripts`, which is how another runner's script runner is named.

## Before you start

- **The cluster's IAM OIDC provider must exist.** Create it once per cluster: `eksctl utils associate-iam-oidc-provider --cluster <name> --approve`. Without it, the plan stops at the provider lookup.
- **Pods need somewhere to run.** Either the cluster has node groups, or you set `fargate_subnet_ids` so this creates a Fargate profile for the runner's namespace.
- **The runner needs its own Matillion registration.** Register the runner in Matillion first, so it has its own client ID and secret.

## Deploy

```bash
cp terraform.tfvars.example terraform.tfvars   # set name, region and cluster_name
terraform init
terraform apply
```

Then install the chart into the runner's namespace with the outputs, as in [Shared Multi-Tenant Platform](../../helm/README.md#shared-multi-tenant-platform):

```bash
helm install "$(terraform output -raw namespace)" ../../helm/runner \
  --namespace "$(terraform output -raw namespace)" --create-namespace \
  -f ../../helm/runner/values-aws.yaml \
  -f my-runner-values.yaml \
  --set aws.region="$(terraform output -raw region)" \
  --set serviceAccount.name="$(terraform output -raw service_account_name)" \
  --set serviceAccount.roleArn="$(terraform output -raw service_account_role_arn)" \
  --set scriptRunner.serviceAccount.name="$(terraform output -raw script_runner_service_account_name)" \
  --set scriptRunner.serviceAccount.roleArn="$(terraform output -raw script_runner_role_arn)"
```

- `values-aws.yaml` sets `cloudProvider: aws`. Without it the chart adds no role annotation, and the runner gets no AWS credentials.
- `my-runner-values.yaml` holds the runner's own credentials and IDs, as in [`values-tenant-example.yaml`](../../helm/runner/values-tenant-example.yaml).
- `aws.region` matters on Fargate, where pods can't look the region up themselves.

If the cluster's Prometheus scales runners, add the namespace to its `scrapeNamespaces` and `networkPolicy.additionalScrapeNamespaces`. Otherwise the runner never scales beyond its minimum, and nothing logs why. The helm README's "Wiring the shared Prometheus" section shows how.

## Secrets

A secret this runner uses must have a name starting with `secret_name_prefix` (`matillion/<name>/`). That covers secrets created from Matillion, and secrets holding OAuth tokens the runner refreshes. Anything else is refused with an AccessDenied error naming the secret.

Secrets Manager has no way to limit listing to some secrets, so the runner can list every secret's metadata in the account (name, description, tags and KMS key ID), though not the values. Keep sensitive information out of secret descriptions and tags in a shared account.

## Compared with `../eks`

- **S3:** both default to every bucket. `s3_bucket_arns` narrows it here.
- **Secrets Manager:** limited to the runner's prefix here; `../eks` grants every secret.
- **IAM and Redshift:** `../eks` grants `iam:CreateRole`, `iam:AttachRolePolicy`, `iam:PassRole` and Redshift administration on everything. This root grants none of them: the runner doesn't call them. On a shared cluster they would let one runner give itself another runner's access.
