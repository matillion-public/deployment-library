# Run with: terraform test  (from modules/azure/container-apps)
#
# disable_script_execution stops the Python Script and Bash Script components
# running on the runner container by pointing their interpreters at paths that
# do not exist. Off by default, so the Container App is unchanged unless the
# caller opts in. Uses a mock provider, so no Azure credentials are needed.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "00000000-0000-0000-0000-000000000001"
      object_id       = "00000000-0000-0000-0000-000000000002"
      subscription_id = "00000000-0000-0000-0000-000000000003"
    }
  }
}

variables {
  name                   = "t"
  location               = "uksouth"
  resource_group_name    = "rg-test"
  random_string_salt     = "abc123"
  subnet_ids             = ["/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/apps"]
  account_id             = "12345"
  agent_id               = "00000000-0000-0000-0000-000000000004"
  client_id              = "client-id"
  client_secret          = "client-secret"
  matillion_cloud_region = "eu1"
}

run "script_execution_enabled_by_default" {
  command = plan

  assert {
    condition = length([
      for e in azurerm_container_app.app.template[0].container[0].env : e
      if contains(["SCRIPT_OOM_PROTECTION_ENABLED", "MTLN_PYTHON_3_COMMAND", "MTLN_BASH_COMMAND"], e.name)
    ]) == 0
    error_message = "With disable_script_execution unset the runner must not get any of the script-disabling variables."
  }
}

run "disable_script_execution_sets_all_three_variables" {
  command = plan

  variables {
    disable_script_execution = true
  }

  assert {
    condition = {
      for e in azurerm_container_app.app.template[0].container[0].env : e.name => e.value
      if contains(["SCRIPT_OOM_PROTECTION_ENABLED", "MTLN_PYTHON_3_COMMAND", "MTLN_BASH_COMMAND"], e.name)
      } == {
      SCRIPT_OOM_PROTECTION_ENABLED = "false"
      MTLN_PYTHON_3_COMMAND         = "/python-script-disabled-on-this-runner"
      MTLN_BASH_COMMAND             = "/bash-script-disabled-on-this-runner"
    }
    error_message = "disable_script_execution must set SCRIPT_OOM_PROTECTION_ENABLED=false and point MTLN_PYTHON_3_COMMAND and MTLN_BASH_COMMAND at missing paths."
  }

  assert {
    condition = alltrue([
      for name in ["CLOUD_PROVIDER", "ACCOUNT_ID", "AGENT_ID", "MATILLION_REGION", "OAUTH_CLIENT_ID", "OAUTH_CLIENT_SECRET"] :
      contains([for e in azurerm_container_app.app.template[0].container[0].env : e.name], name)
    ])
    error_message = "Disabling script execution must leave the runner's own variables in place."
  }
}
