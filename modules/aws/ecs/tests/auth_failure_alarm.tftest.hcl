# Run with: terraform test  (from modules/aws/ecs)
#
# A runner that cannot authenticate keeps running, so the module counts
# authentication failures in the runner task log and optionally alarms on them.
# Uses a mock provider, so no AWS credentials or resources are needed.

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

# terraform test cannot evaluate a CloudWatch filter pattern. The pattern is a single quoted
# phrase, which CloudWatch matches as a case-sensitive substring, so these runs check the phrase
# against two sample lines with strcontains: the runner's failed token request with a wrong client
# secret, and a pipeline connector's OAuth failure, which the filter must not count.

run "metric_filter_without_alarm_by_default" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_metric_filter.runner_auth_failures.log_group_name == aws_cloudwatch_log_group.matillion_dpc_runner_task_logs.name
    error_message = "The metric filter must read the runner task log group."
  }

  assert {
    condition     = aws_cloudwatch_log_metric_filter.runner_auth_failures.pattern == "\"Recoverable error caught [[invalid_\""
    error_message = "The metric filter must be the single quoted phrase \"Recoverable error caught [[invalid_\"."
  }

  assert {
    condition     = strcontains("WARN Recoverable error caught [[invalid_token_response] An error occurred while attempting to retrieve the OAuth 2.0 Access Token Response: 401 Unauthorized on POST request for \"https://keycloak.core-dev.matillion.com/realms/etl-agents/protocol/openid-connect/token\"]. Reconnect will be attempted.", trim(aws_cloudwatch_log_metric_filter.runner_auth_failures.pattern, "\""))
    error_message = "The metric filter must match the runner's failed token request."
  }

  assert {
    condition     = !strcontains("ERROR OAuth token request failed: {\"error\":\"invalid_client\",\"error_description\":\"AADSTS7000222: The provided client secret keys for app are expired.\"}", trim(aws_cloudwatch_log_metric_filter.runner_auth_failures.pattern, "\""))
    error_message = "The metric filter must not match a pipeline connector's OAuth failure."
  }

  assert {
    condition     = aws_cloudwatch_log_metric_filter.runner_auth_failures.metric_transformation[0].value == "1"
    error_message = "Each matching log event must add 1 to the metric."
  }

  assert {
    condition     = aws_cloudwatch_log_metric_filter.runner_auth_failures.name == "t-runner-auth-failures"
    error_message = "The metric filter name should be derived from the module name."
  }

  assert {
    condition     = aws_cloudwatch_log_metric_filter.runner_auth_failures.metric_transformation[0].name == "t-runner-auth-failures"
    error_message = "The metric name should be derived from the module name."
  }

  assert {
    condition     = aws_cloudwatch_log_metric_filter.runner_auth_failures.metric_transformation[0].namespace == "Matillion/Runner"
    error_message = "The metric must be published in the Matillion/Runner namespace."
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.runner_auth_failures) == 0
    error_message = "No alarm should be created when auth_failure_alarm_actions is empty."
  }
}

run "alarm_when_actions_are_set" {
  command = plan

  variables {
    auth_failure_alarm_actions = ["arn:aws:sns:eu-west-1:123456789012:alerts"]
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.runner_auth_failures) == 1
    error_message = "One alarm should be created when auth_failure_alarm_actions is set."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.runner_auth_failures[0].alarm_actions == toset(["arn:aws:sns:eu-west-1:123456789012:alerts"])
    error_message = "The alarm must notify the ARNs in auth_failure_alarm_actions."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.runner_auth_failures[0].ok_actions == toset(["arn:aws:sns:eu-west-1:123456789012:alerts"])
    error_message = "The alarm must notify the same ARNs when it returns to OK."
  }

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.runner_auth_failures[0].statistic == "Sum" &&
      aws_cloudwatch_metric_alarm.runner_auth_failures[0].period == 300 &&
      aws_cloudwatch_metric_alarm.runner_auth_failures[0].evaluation_periods == 3 &&
      aws_cloudwatch_metric_alarm.runner_auth_failures[0].datapoints_to_alarm == 2 &&
      aws_cloudwatch_metric_alarm.runner_auth_failures[0].threshold == 1 &&
      aws_cloudwatch_metric_alarm.runner_auth_failures[0].comparison_operator == "GreaterThanOrEqualToThreshold"
    )
    error_message = "The alarm must fire when the 5-minute sum is 1 or more in 2 of 3 periods."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.runner_auth_failures[0].treat_missing_data == "notBreaching"
    error_message = "Missing data must not put the alarm into ALARM."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.runner_auth_failures[0].metric_name == aws_cloudwatch_log_metric_filter.runner_auth_failures.metric_transformation[0].name
    error_message = "The alarm must watch the metric the filter publishes."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.runner_auth_failures[0].namespace == aws_cloudwatch_log_metric_filter.runner_auth_failures.metric_transformation[0].namespace
    error_message = "The alarm must watch the namespace the filter publishes to."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.runner_auth_failures[0].alarm_name == "t-runner-auth-failures"
    error_message = "The alarm name should be derived from the module name."
  }
}

run "overridden_names" {
  command = plan

  variables {
    auth_failure_alarm_actions = ["arn:aws:sns:eu-west-1:123456789012:alerts"]
    resource_names = {
      auth_failure_metric_filter = "custom-auth-filter"
      auth_failure_alarm         = "custom-auth-alarm"
    }
  }

  assert {
    condition     = aws_cloudwatch_log_metric_filter.runner_auth_failures.name == "custom-auth-filter"
    error_message = "The metric filter name should follow a resource_names override."
  }

  assert {
    condition     = aws_cloudwatch_log_metric_filter.runner_auth_failures.metric_transformation[0].name == "custom-auth-filter"
    error_message = "The metric name should follow a resource_names override."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.runner_auth_failures[0].alarm_name == "custom-auth-alarm"
    error_message = "The alarm name should follow a resource_names override."
  }
}
