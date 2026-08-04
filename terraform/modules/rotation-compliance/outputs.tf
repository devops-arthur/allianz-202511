output "custom_rule_name" {
  description = "Name of the custom Config rule that checks the key generation."
  value       = aws_config_config_rule.current_key_generation.name
}

output "managed_rule_names" {
  description = "Names of the deployed managed Config rules."
  value       = sort(keys(var.managed_rules))
}

output "lambda_function_arn" {
  description = "ARN of the rule Lambda."
  value       = aws_lambda_function.rule.arn
}

output "lambda_role_arn" {
  description = "ARN of the rule Lambda role. Must be granted kms:DescribeKey on the central keys."
  value       = aws_iam_role.lambda.arn
}

output "notification_topic_arn" {
  description = "SNS topic non-compliance notifications are published to."
  value       = local.topic_arn
}
