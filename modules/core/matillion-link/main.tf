# modules/core/matillion-link
#
# Links the deployed agent to Matillion Cloud. Provider-agnostic configuration
# contract: it holds the account/region and the (sensitive) OAuth client secret
# that the compute modules inject into the agent runtime. It provisions no cloud
# resources — the secret is stored in the provider-native secret store by the
# auth modules (Secrets Manager / Key Vault / Secret Manager), which this module
# feeds. Keeping the secret here (write-only, sensitive) centralises the link
# configuration for the composer.
