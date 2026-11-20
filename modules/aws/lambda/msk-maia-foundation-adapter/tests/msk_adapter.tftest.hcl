# Run with: terraform test  (from modules/aws/lambda/msk-maia-foundation-adapter)
#
# What the module provisions for a set of MSK topics, and the inputs it refuses.
# Uses a mock provider, so no AWS credentials or resources are needed.

mock_provider "aws" {
  mock_data "aws_secretsmanager_secret" {
    defaults = { arn = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:matillion-maia-foundation-AbCdEf" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
}

variables {
  aws_region        = "eu-west-1"
  image_uri         = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/maia-queue-adapter:current"
  secret_name       = "matillion-maia-foundation"
  cluster_arn       = "arn:aws:kafka:eu-west-1:123456789012:cluster/orders/abc-1"
  topics            = ["orders", "refunds"]
  scram_secret_arn  = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:AmazonMSK_maia-AbCdEf"
  scram_kms_key_arn = "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
  failure_topic     = "maia-trigger-failures"
}

run "each_topic_gets_a_mapping_in_one_poller_group" {
  command = plan

  assert {
    condition     = keys(aws_lambda_event_source_mapping.msk) == ["orders", "refunds"]
    error_message = "Each topic must get its own mapping."
  }

  assert {
    condition     = length(distinct([for m in aws_lambda_event_source_mapping.msk : m.provisioned_poller_config[0].poller_group_name])) == 1
    error_message = "Every topic's mapping must share one poller group, or each is billed for its own."
  }

  assert {
    condition     = length(distinct([for m in aws_lambda_event_source_mapping.msk : m.amazon_managed_kafka_event_source_config[0].consumer_group_id])) == 2
    error_message = "Each mapping needs its own consumer group."
  }

  # Without provisioned mode Kafka ignores partial batch responses and the retry
  # limit, and a failing record is retried until it expires.
  assert {
    condition = alltrue([for m in aws_lambda_event_source_mapping.msk : (
      m.function_response_types == toset(["ReportBatchItemFailures"])
      && m.maximum_retry_attempts == 3
      && m.destination_config[0].on_failure[0].destination_arn == "kafka://maia-trigger-failures"
    )])
    error_message = "Each mapping must report partial batch failures, stop retrying and send what is left to the failure topic."
  }

  assert {
    condition     = aws_lambda_function.this.environment[0].variables["MATILLION_AWS_EVENT_SOURCE"] == "msk"
    error_message = "The function must be told it is invoked by MSK."
  }

  assert {
    condition = (
      toset([for s in data.aws_iam_policy_document.lambda.statement : s.sid]) ==
      toset(["ReadSecret", "ReadProjectMappings", "ListScramSecrets", "ReadScramSecret", "DecryptScramSecret"])
    )
    error_message = "The role needs the Maia Foundation secret, the mapping table and the SCRAM grants, and nothing else inline."
  }
}

run "each_topic_alarms_on_its_failures" {
  command = plan

  assert {
    condition     = keys(aws_cloudwatch_metric_alarm.failure_topic) == ["orders", "refunds"]
    error_message = "Each topic needs an alarm for records reaching the failure topic."
  }

  assert {
    condition     = alltrue([for m in aws_lambda_event_source_mapping.msk : m.metrics_config[0].metrics == toset(["EventCount"])])
    error_message = "The failure topic alarms read metrics that each mapping must publish."
  }

  assert {
    condition     = alltrue([for topic, alarm in aws_cloudwatch_metric_alarm.failure_topic : endswith(alarm.alarm_name, "-${topic}")])
    error_message = "Each failure-topic alarm name must keep its topic whole, so two long topics cannot collide onto one name."
  }
}

run "refuses_a_failure_topic_it_also_consumes" {
  command = plan

  variables {
    topics = ["orders", "maia-trigger-failures"]
  }

  expect_failures = [var.failure_topic]
}

run "refuses_more_minimum_than_maximum_pollers" {
  command = plan

  variables {
    minimum_pollers = 20
  }

  expect_failures = [var.maximum_pollers]
}

run "refuses_an_unsupported_starting_position" {
  command = plan

  variables {
    starting_position = "AT_TIMESTAMP"
  }

  expect_failures = [var.starting_position]
}

run "passes_topic_routes_to_the_function" {
  command = plan

  variables {
    topic_routes = {
      orders = {
        project          = "CustomerDataPipeline"
        environment      = "prod"
        pipeline         = "mskLoad/LoadOrderEvent"
        payload_variable = "orderEvent"
      }
    }
  }

  assert {
    condition = jsondecode(aws_lambda_function.this.environment[0].variables["MATILLION_MSK_TOPIC_ROUTES"]) == {
      orders = {
        project          = "CustomerDataPipeline"
        environment      = "prod"
        pipeline         = "mskLoad/LoadOrderEvent"
        payload_variable = "orderEvent"
      }
    }
    error_message = "The function must receive the routes as JSON keyed by topic."
  }
}

run "refuses_a_route_for_a_topic_it_does_not_read" {
  command = plan

  variables {
    topic_routes = {
      payments = {
        project          = "CustomerDataPipeline"
        environment      = "prod"
        pipeline         = "mskLoad/LoadPayment"
        payload_variable = "paymentEvent"
      }
    }
  }

  expect_failures = [var.topic_routes]
}

run "refuses_a_payload_variable_that_shadows_kafka_metadata" {
  command = plan

  variables {
    topic_routes = {
      orders = {
        project          = "CustomerDataPipeline"
        environment      = "prod"
        pipeline         = "mskLoad/LoadOrderEvent"
        payload_variable = "kafkaOffset"
      }
    }
  }

  expect_failures = [var.topic_routes]
}

run "refuses_an_empty_payload_variable" {
  command = plan

  variables {
    topic_routes = {
      orders = {
        project          = "CustomerDataPipeline"
        environment      = "prod"
        pipeline         = "mskLoad/LoadOrderEvent"
        payload_variable = ""
      }
    }
  }

  expect_failures = [var.topic_routes]
}

run "refuses_an_empty_project" {
  command = plan

  variables {
    topic_routes = {
      orders = {
        project          = ""
        environment      = "prod"
        pipeline         = "mskLoad/LoadOrderEvent"
        payload_variable = "orderEvent"
      }
    }
  }

  expect_failures = [var.topic_routes]
}

run "refuses_routes_that_exceed_the_env_var_budget" {
  command = plan

  variables {
    topics = [for i in range(30) : "topic-${i}"]
    topic_routes = {
      for i in range(30) : "topic-${i}" => {
        project          = "CustomerDataPipeline"
        environment      = "prod"
        pipeline         = "mskLoad/LoadOrderEvent"
        payload_variable = "orderEvent"
      }
    }
  }

  expect_failures = [var.topic_routes]
}

run "refuses_a_duplicate_topic" {
  command = plan

  variables {
    topics = ["orders", "orders"]
  }

  expect_failures = [var.topics]
}
