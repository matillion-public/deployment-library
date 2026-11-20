# Run with: terraform test  (from modules/aws/ecs)
#
# disable_script_execution stops the Python Script and Bash Script components
# running on the runner container by pointing their interpreters at paths that
# do not exist. Off by default, so the task definition is unchanged unless the
# caller opts in. Uses a mock provider, so no AWS credentials are needed.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_resource "aws_security_group" {
    defaults = { id = "sg-0runner0000000000" }
  }
}

variables {
  name                           = "t"
  region                         = "eu-west-1"
  account_id                     = "00000000-0000-0000-0000-000000000000"
  agent_id                       = "00000000-0000-0000-0000-000000000001"
  vpc_id                         = "vpc-0000000000000000"
  subnet_ids                     = ["subnet-00000000000000001"]
  security_group_ids             = []
  runner_task_role_execution_arn = "arn:aws:iam::123456789012:role/exec"
  runner_task_role_arn           = "arn:aws:iam::123456789012:role/task"
  runner_secret_arn              = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:runner"
  tags                           = { ManagedBy = "terraform" }
}

run "script_execution_enabled_by_default" {
  command = plan

  assert {
    condition = length([
      for e in jsondecode(aws_ecs_task_definition.matillion_dpc_runner.container_definitions)[0].environment : e
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
      for e in jsondecode(aws_ecs_task_definition.matillion_dpc_runner.container_definitions)[0].environment : e.name => e.value
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
      for name in ["ACCOUNT_ID", "AGENT_ID", "MATILLION_REGION", "CLOUD_PROVIDER", "EXPORT_LOGS"] :
      contains([for e in jsondecode(aws_ecs_task_definition.matillion_dpc_runner.container_definitions)[0].environment : e.name], name)
    ])
    error_message = "Disabling script execution must leave the runner's own variables in place."
  }
}
