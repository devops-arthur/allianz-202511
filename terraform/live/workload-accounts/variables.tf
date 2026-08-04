variable "region" {
  description = "AWS region the workload accounts operate in."
  type        = string
  default     = "us-east-1"
}

variable "workload_accounts" {
  description = <<-EOT
    Map of environment name to workload account ID. Must contain exactly the keys "dev", "int",
    and "prod" to match the provider aliases defined in providers.tf.
  EOT
  type        = map(string)

  validation {
    condition     = alltrue([for id in values(var.workload_accounts) : can(regex("^[0-9]{12}$", id))])
    error_message = "Each workload account must be a 12-digit AWS account ID."
  }

  validation {
    condition     = alltrue([for k in ["dev", "int", "prod"] : contains(keys(var.workload_accounts), k)])
    error_message = "workload_accounts must contain the keys 'dev', 'int', and 'prod'."
  }
}

variable "terraform_execution_role_name" {
  description = "Name of the IAM role Terraform assumes in each workload account."
  type        = string
  default     = "terraform-workload-admin"
}

variable "key_account_id" {
  description = "Account ID of the security account that owns the centrally managed KMS keys."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.key_account_id))
    error_message = "key_account_id must be a 12-digit AWS account ID."
  }
}

variable "key_region" {
  description = "Region the KMS keys live in. Defaults to var.region when null."
  type        = string
  default     = null
}

variable "config_delivery_bucket_name" {
  description = "Central S3 bucket (in the security account) that AWS Config delivers snapshots and history to."
  type        = string
}

variable "config_delivery_frequency" {
  description = "How often AWS Config snapshots are delivered to the central bucket."
  type        = string
  default     = "TwentyFour_Hours"

  validation {
    condition = contains(
      ["One_Hour", "Three_Hours", "Six_Hours", "Twelve_Hours", "TwentyFour_Hours"],
      var.config_delivery_frequency,
    )
    error_message = "Invalid delivery frequency."
  }
}

variable "record_all_supported_resources" {
  description = "Record every supported resource type. Set to false to limit recording to the encryption-relevant types (cheaper but blinds other rules)."
  type        = bool
  default     = false
}

variable "include_global_resource_types" {
  description = "Record global resources (IAM) in the Config recorder. Enable in exactly one region per account."
  type        = bool
  default     = false
}

variable "compliance_role_name" {
  description = <<-EOT
    Name of the Lambda execution role deployed in every workload account. Must match
    rotation_compliance_role_name in the security-keys root module because the key policy
    in the security account grants kms:DescribeKey to exactly this role ARN.
  EOT
  type        = string
  default     = "config-rule-kms-rotation-compliance"
}

variable "rule_name" {
  description = "Name of the custom AWS Config rule deployed in every workload account."
  type        = string
  default     = "kms-encrypted-with-current-key-generation"
}

variable "evaluation_frequency" {
  description = "Frequency of the periodic full sweep performed by the compliance rule."
  type        = string
  default     = "TwentyFour_Hours"

  validation {
    condition = contains(
      ["One_Hour", "Three_Hours", "Six_Hours", "Twelve_Hours", "TwentyFour_Hours"],
      var.evaluation_frequency,
    )
    error_message = "Invalid evaluation frequency."
  }
}

variable "notify_on_compliance_change" {
  description = "Create an EventBridge rule and SNS topic that fire whenever a resource becomes NON_COMPLIANT."
  type        = bool
  default     = true
}

variable "notification_topic_arns" {
  description = <<-EOT
    Optional pre-existing SNS topic ARNs to use for compliance-change notifications, keyed by
    environment name. When an environment is not listed here, a new topic is created automatically.
  EOT
  type        = map(string)
  default     = {}
}

variable "log_retention_in_days" {
  description = "CloudWatch Logs retention for the compliance rule Lambda in every workload account."
  type        = number
  default     = 365
}

variable "default_tags" {
  description = "Tags applied to every resource in this root module."
  type        = map(string)
  default = {
    Project   = "encryption-management"
    ManagedBy = "terraform"
  }
}
