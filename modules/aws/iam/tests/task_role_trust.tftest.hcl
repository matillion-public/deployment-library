# Run with: terraform test  (from modules/aws/iam)
#
# The runner task role is assumed only by ECS tasks, and the module creates no
# EC2 instance profile for it. Uses a mock provider, so no AWS credentials or
# resources are needed.

mock_provider "aws" {}

variables {
  name              = "t"
  runner_secret_arn = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:runner"
}

run "task_role_trusts_only_ecs_tasks" {
  command = plan

  assert {
    condition     = length(jsondecode(aws_iam_role.ecs_task_role.assume_role_policy).Statement) == 1
    error_message = "Task role trust policy must have a single statement."
  }

  assert {
    condition     = jsondecode(aws_iam_role.ecs_task_role.assume_role_policy).Statement[0].Principal.Service == ["ecs-tasks.amazonaws.com"]
    error_message = "Task role must trust only ecs-tasks.amazonaws.com."
  }
}

# terraform test cannot enumerate planned resource types, so this reads the
# module's own configuration: no declared instance profile means none is planned.
run "no_instance_profile_is_declared" {
  command = plan

  assert {
    condition = length(flatten([
      for config_file in fileset(path.module, "*.tf") :
      regexall("resource\\s+\"aws_iam_instance_profile\"", file("${path.module}/${config_file}"))
    ])) == 0
    error_message = "The module must not declare an aws_iam_instance_profile."
  }
}
