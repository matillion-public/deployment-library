# Run with: terraform test  (from modules/core/compute-ecs)
#
# disable_script_execution stops the Python Script and Bash Script components
# running on the agent container by pointing their interpreters at paths that do
# not exist. Off by default, so the task definition is unchanged unless the
# caller opts in. Uses a mock provider, so no AWS credentials are needed.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
}

variables {
  region         = "eu-west-1"
  agent_role_arn = "arn:aws:iam::123456789012:role/agent"
  subnet_ids     = ["subnet-00000000000000001"]
  account_id     = "12345"
  agent_id       = "00000000-0000-0000-0000-000000000001"
}

run "script_execution_enabled_by_default" {
  command = plan

  assert {
    condition = [
      for e in jsondecode(aws_ecs_task_definition.agent.container_definitions)[0].environment : e.name
      ] == ["MATILLION_ACCOUNT_ID", "MATILLION_AGENT_ID", "MATILLION_REGION"]
    error_message = "With disable_script_execution unset the agent environment must be exactly the three base variables."
  }
}

run "disable_script_execution_sets_all_three_variables" {
  command = plan

  variables {
    disable_script_execution = true
  }

  assert {
    condition = {
      for e in jsondecode(aws_ecs_task_definition.agent.container_definitions)[0].environment : e.name => e.value
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
      for name in ["MATILLION_ACCOUNT_ID", "MATILLION_AGENT_ID", "MATILLION_REGION"] :
      contains([for e in jsondecode(aws_ecs_task_definition.agent.container_definitions)[0].environment : e.name], name)
    ])
    error_message = "Disabling script execution must leave the agent's own variables in place."
  }
}
