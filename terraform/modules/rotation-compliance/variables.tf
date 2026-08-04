variable "environment" {
  description = "Environment of this workload account (dev, int, prod). Used to build alias/<environment>-<service>."
  type        = string
}

variable "key_account_id" {
  description = "Account ID of the security account that owns the KMS keys."
  type        = string
}

variable "key_region" {
  description = "Region the KMS keys live in. Defaults to the current region."
  type        = string
  default     = null
}

variable "service_by_resource_type" {
  description = "Config resource type -> key service suffix, i.e. which alias a resource type must be encrypted with."
  type        = map(string)
  default = {
    "AWS::S3::Bucket"       = "s3"
    "AWS::RDS::DBInstance"  = "rds"
    "AWS::RDS::DBCluster"   = "rds"
    "AWS::DynamoDB::Table"  = "ddb"
  }
}

variable "alias_template" {
  description = "Naming convention for the service aliases."
  type        = string
  default     = "alias/{environment}-{service}"
}

variable "compliance_role_name" {
  description = <<-EOT
    Name of the Lambda execution role. Must match rotation_compliance_role_name in the security-keys
    root module, because the key policy grants kms:DescribeKey to exactly this role ARN.
  EOT
  type        = string
  default     = "config-rule-kms-rotation-compliance"
}

variable "rule_name" {
  description = "Name of the custom AWS Config rule."
  type        = string
  default     = "kms-encrypted-with-current-key-generation"
}

variable "evaluation_frequency" {
  description = "Frequency of the periodic full sweep."
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

variable "lambda_timeout" {
  description = "Lambda timeout in seconds. The periodic sweep calls one API per resource, so scale this with the account size."
  type        = number
  default     = 300
}

variable "lambda_memory_size" {
  description = "Lambda memory in MB."
  type        = number
  default     = 512
}

variable "log_retention_in_days" {
  description = "CloudWatch Logs retention for the rule Lambda."
  type        = number
  default     = 365
}

variable "managed_rules" {
  description = <<-EOT
    AWS Config managed rules deployed alongside the custom rule. These answer "is it encrypted at
    all"; the custom rule answers "is it encrypted with the current key generation".
  EOT
  type = map(object({
    source_identifier            = string
    input_parameters             = optional(map(string), {})
    maximum_execution_frequency  = optional(string)
    scope_resource_types         = optional(list(string), [])
  }))
  default = {
    s3-bucket-server-side-encryption-enabled = {
      source_identifier    = "S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED"
      scope_resource_types = ["AWS::S3::Bucket"]
    }
    s3-default-encryption-kms = {
      source_identifier    = "S3_DEFAULT_ENCRYPTION_KMS"
      scope_resource_types = ["AWS::S3::Bucket"]
    }
    rds-storage-encrypted = {
      source_identifier    = "RDS_STORAGE_ENCRYPTED"
      scope_resource_types = ["AWS::RDS::DBInstance"]
    }
    rds-snapshot-encrypted = {
      source_identifier    = "RDS_SNAPSHOT_ENCRYPTED"
      scope_resource_types = ["AWS::RDS::DBSnapshot", "AWS::RDS::DBClusterSnapshot"]
    }
    dynamodb-table-encrypted-kms = {
      source_identifier    = "DYNAMODB_TABLE_ENCRYPTED_KMS"
      scope_resource_types = ["AWS::DynamoDB::Table"]
    }
    encrypted-volumes = {
      source_identifier    = "ENCRYPTED_VOLUMES"
      scope_resource_types = ["AWS::EC2::Volume"]
    }
  }
}

variable "notification_topic_arn" {
  description = "Existing SNS topic for compliance-change notifications. When null, a topic is created."
  type        = string
  default     = null
}

variable "notify_on_compliance_change" {
  description = "Send an EventBridge notification whenever a resource becomes NON_COMPLIANT for the encryption rules."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to created resources."
  type        = map(string)
  default     = {}
}
