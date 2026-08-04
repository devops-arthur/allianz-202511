# ---------------------------------------------------------------------------
# AWS Config baseline - one recorder + delivery channel per workload account.
# Each account delivers its configuration history to a central S3 bucket in
# the security account.
# ---------------------------------------------------------------------------

module "config_baseline_dev" {
  source = "../../modules/config-baseline"

  providers = { aws = aws.dev }

  delivery_bucket_name           = var.config_delivery_bucket_name
  delivery_frequency             = var.config_delivery_frequency
  record_all_supported_resources = var.record_all_supported_resources
  include_global_resource_types  = var.include_global_resource_types

  tags = { Environment = "dev" }
}

module "config_baseline_int" {
  source = "../../modules/config-baseline"

  providers = { aws = aws.int }

  delivery_bucket_name           = var.config_delivery_bucket_name
  delivery_frequency             = var.config_delivery_frequency
  record_all_supported_resources = var.record_all_supported_resources
  include_global_resource_types  = var.include_global_resource_types

  tags = { Environment = "int" }
}

module "config_baseline_prod" {
  source = "../../modules/config-baseline"

  providers = { aws = aws.prod }

  delivery_bucket_name           = var.config_delivery_bucket_name
  delivery_frequency             = var.config_delivery_frequency
  record_all_supported_resources = var.record_all_supported_resources
  include_global_resource_types  = var.include_global_resource_types

  tags = { Environment = "prod" }
}

# ---------------------------------------------------------------------------
# Rotation compliance rule - one Lambda-backed Config rule per workload account.
# The rule resolves alias/<env>-<service> in the security account at evaluation
# time and flags any resource still encrypted under a previous key generation.
# ---------------------------------------------------------------------------

module "rotation_compliance_dev" {
  source = "../../modules/rotation-compliance"

  providers = { aws = aws.dev }

  environment          = "dev"
  key_account_id       = var.key_account_id
  key_region           = var.key_region
  compliance_role_name = var.compliance_role_name
  rule_name            = var.rule_name
  evaluation_frequency = var.evaluation_frequency

  notify_on_compliance_change = var.notify_on_compliance_change
  notification_topic_arn      = lookup(var.notification_topic_arns, "dev", null)
  log_retention_in_days       = var.log_retention_in_days

  tags = { Environment = "dev" }

  depends_on = [module.config_baseline_dev]
}

module "rotation_compliance_int" {
  source = "../../modules/rotation-compliance"

  providers = { aws = aws.int }

  environment          = "int"
  key_account_id       = var.key_account_id
  key_region           = var.key_region
  compliance_role_name = var.compliance_role_name
  rule_name            = var.rule_name
  evaluation_frequency = var.evaluation_frequency

  notify_on_compliance_change = var.notify_on_compliance_change
  notification_topic_arn      = lookup(var.notification_topic_arns, "int", null)
  log_retention_in_days       = var.log_retention_in_days

  tags = { Environment = "int" }

  depends_on = [module.config_baseline_int]
}

module "rotation_compliance_prod" {
  source = "../../modules/rotation-compliance"

  providers = { aws = aws.prod }

  environment          = "prod"
  key_account_id       = var.key_account_id
  key_region           = var.key_region
  compliance_role_name = var.compliance_role_name
  rule_name            = var.rule_name
  evaluation_frequency = var.evaluation_frequency

  notify_on_compliance_change = var.notify_on_compliance_change
  notification_topic_arn      = lookup(var.notification_topic_arns, "prod", null)
  log_retention_in_days       = var.log_retention_in_days

  tags = { Environment = "prod" }

  depends_on = [module.config_baseline_prod]
}
