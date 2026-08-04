output "config_recorder_names" {
  description = "Name of the AWS Config recorder in each workload account."
  value = {
    dev  = module.config_baseline_dev.recorder_name
    int  = module.config_baseline_int.recorder_name
    prod = module.config_baseline_prod.recorder_name
  }
}

output "config_role_arns" {
  description = "ARN of the AWS Config service role in each workload account."
  value = {
    dev  = module.config_baseline_dev.role_arn
    int  = module.config_baseline_int.role_arn
    prod = module.config_baseline_prod.role_arn
  }
}

output "compliance_rule_names" {
  description = "Name of the custom Config rule that checks the KMS key generation in each workload account."
  value = {
    dev  = module.rotation_compliance_dev.custom_rule_name
    int  = module.rotation_compliance_int.custom_rule_name
    prod = module.rotation_compliance_prod.custom_rule_name
  }
}

output "compliance_lambda_arns" {
  description = "ARN of the compliance-check Lambda function in each workload account."
  value = {
    dev  = module.rotation_compliance_dev.lambda_function_arn
    int  = module.rotation_compliance_int.lambda_function_arn
    prod = module.rotation_compliance_prod.lambda_function_arn
  }
}

output "compliance_lambda_role_arns" {
  description = <<-EOT
    ARN of the Lambda execution role in each workload account. These ARNs must be added to the
    compliance_reader_arns (or auditor_role_arns) of the security-keys root module so the Lambda
    can call kms:DescribeKey cross-account to resolve the current key generation.
  EOT
  value = {
    dev  = module.rotation_compliance_dev.lambda_role_arn
    int  = module.rotation_compliance_int.lambda_role_arn
    prod = module.rotation_compliance_prod.lambda_role_arn
  }
}

output "notification_topic_arns" {
  description = "SNS topic ARNs that receive NON_COMPLIANT alerts in each workload account."
  value = {
    dev  = module.rotation_compliance_dev.notification_topic_arn
    int  = module.rotation_compliance_int.notification_topic_arn
    prod = module.rotation_compliance_prod.notification_topic_arn
  }
}

output "managed_rule_names" {
  description = "Names of the managed Config rules deployed in every workload account."
  value = {
    dev  = module.rotation_compliance_dev.managed_rule_names
    int  = module.rotation_compliance_int.managed_rule_names
    prod = module.rotation_compliance_prod.managed_rule_names
  }
}
