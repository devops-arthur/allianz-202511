data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
  partition  = data.aws_partition.current.partition
  key_region = coalesce(var.key_region, local.region)

  in_scope_resource_types = keys(var.service_by_resource_type)

  topic_arn = var.notification_topic_arn != null ? var.notification_topic_arn : one(aws_sns_topic.compliance[*].arn)

  all_rule_names = concat([var.rule_name], keys(var.managed_rules))
}

# ---------------------------------------------------------------------------------------------------
# Lambda backing the custom rule
# ---------------------------------------------------------------------------------------------------
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/index.py"
  output_path = "${path.module}/.build/rotation-compliance.zip"
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  # Fixed name: the cross-account key policy in the security account references this exact ARN.
  name               = var.compliance_role_name
  description        = "Execution role for the AWS Config rule that checks BYOK key rotation compliance"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = var.tags
}

data "aws_iam_policy_document" "lambda" {
  statement {
    sid    = "Logs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.lambda.arn}:*"]
  }

  statement {
    sid       = "ReportEvaluations"
    effect    = "Allow"
    actions   = ["config:PutEvaluations"]
    resources = ["*"]
  }

  # Read-only discovery of the resources being evaluated. No data-plane access anywhere.
  statement {
    sid    = "InspectEncryptionConfiguration"
    effect = "Allow"
    actions = [
      "s3:GetBucketLocation",
      "s3:GetEncryptionConfiguration",
      "s3:ListAllMyBuckets",
      "rds:DescribeDBClusters",
      "rds:DescribeDBInstances",
      "dynamodb:DescribeTable",
      "dynamodb:ListTables",
    ]
    resources = ["*"]
  }

  # Resolve alias/<env>-<service> in the security account to the current key ARN.
  statement {
    sid       = "ResolveCentralKeyAliases"
    effect    = "Allow"
    actions   = ["kms:DescribeKey"]
    resources = ["arn:${local.partition}:kms:${local.key_region}:${var.key_account_id}:key/*"]
  }

  statement {
    sid       = "ResolveCentralKeyAliasNames"
    effect    = "Allow"
    actions   = ["kms:DescribeKey"]
    resources = ["arn:${local.partition}:kms:${local.key_region}:${var.key_account_id}:alias/*"]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "rotation-compliance"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda.json
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.rule_name}"
  retention_in_days = var.log_retention_in_days
  tags              = var.tags
}

resource "aws_lambda_function" "rule" {
  function_name = var.rule_name
  description   = "AWS Config custom rule: resource must be encrypted with the current BYOK key generation"
  role          = aws_iam_role.lambda.arn
  handler       = "index.lambda_handler"
  runtime       = "python3.12"
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size

  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      ENVIRONMENT              = var.environment
      KEY_ACCOUNT_ID           = var.key_account_id
      KEY_REGION               = local.key_region
      PARTITION                = local.partition
      ALIAS_TEMPLATE           = var.alias_template
      SERVICE_BY_RESOURCE_TYPE = jsonencode(var.service_by_resource_type)
    }
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy.lambda,
    aws_cloudwatch_log_group.lambda,
  ]
}

resource "aws_lambda_permission" "config" {
  statement_id   = "AllowAWSConfigInvoke"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.rule.function_name
  principal      = "config.amazonaws.com"
  source_account = local.account_id
}

# ---------------------------------------------------------------------------------------------------
# The custom rule: change-triggered for immediate feedback, periodic for the point-in-time inventory
# ---------------------------------------------------------------------------------------------------
resource "aws_config_config_rule" "current_key_generation" {
  name        = var.rule_name
  description = "Resources must be encrypted with the current generation of their centrally managed BYOK key"

  source {
    owner             = "CUSTOM_LAMBDA"
    source_identifier = aws_lambda_function.rule.arn

    source_detail {
      event_source = "aws.config"
      message_type = "ConfigurationItemChangeNotification"
    }

    source_detail {
      event_source = "aws.config"
      message_type = "OversizedConfigurationItemChangeNotification"
    }

    source_detail {
      event_source                = "aws.config"
      message_type                = "ScheduledNotification"
      maximum_execution_frequency = var.evaluation_frequency
    }
  }

  scope {
    compliance_resource_types = local.in_scope_resource_types
  }

  tags = var.tags

  depends_on = [aws_lambda_permission.config]
}

# ---------------------------------------------------------------------------------------------------
# Managed rules - the "encrypted at all" baseline
# ---------------------------------------------------------------------------------------------------
resource "aws_config_config_rule" "managed" {
  for_each = var.managed_rules

  name             = each.key
  input_parameters = length(each.value.input_parameters) > 0 ? jsonencode(each.value.input_parameters) : null

  source {
    owner             = "AWS"
    source_identifier = each.value.source_identifier
  }

  dynamic "scope" {
    for_each = length(each.value.scope_resource_types) > 0 ? [1] : []

    content {
      compliance_resource_types = each.value.scope_resource_types
    }
  }

  maximum_execution_frequency = each.value.maximum_execution_frequency

  tags = var.tags
}

# ---------------------------------------------------------------------------------------------------
# Alerting on compliance changes
# ---------------------------------------------------------------------------------------------------
resource "aws_sns_topic" "compliance" {
  count = var.notification_topic_arn == null && var.notify_on_compliance_change ? 1 : 0

  name              = "${var.rule_name}-alerts"
  kms_master_key_id = "alias/aws/sns"
  tags              = var.tags
}

data "aws_iam_policy_document" "topic" {
  count = var.notification_topic_arn == null && var.notify_on_compliance_change ? 1 : 0

  statement {
    sid       = "AllowEventBridgePublish"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.compliance[0].arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_sns_topic_policy" "compliance" {
  count = var.notification_topic_arn == null && var.notify_on_compliance_change ? 1 : 0

  arn    = aws_sns_topic.compliance[0].arn
  policy = data.aws_iam_policy_document.topic[0].json
}

resource "aws_cloudwatch_event_rule" "compliance_change" {
  count = var.notify_on_compliance_change ? 1 : 0

  name        = "${var.rule_name}-compliance-change"
  description = "A resource stopped being compliant with one of the encryption/rotation rules"

  event_pattern = jsonencode({
    source      = ["aws.config"]
    detail-type = ["Config Rules Compliance Change"]
    detail = {
      messageType = ["ComplianceChangeNotification"]
      configRuleName = local.all_rule_names
      newEvaluationResult = {
        complianceType = ["NON_COMPLIANT"]
      }
    }
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "compliance_change" {
  count = var.notify_on_compliance_change ? 1 : 0

  rule      = aws_cloudwatch_event_rule.compliance_change[0].name
  target_id = "sns"
  arn       = local.topic_arn
}
