variable "name" {
  description = "Name of the configuration recorder and delivery channel."
  type        = string
  default     = "default"
}

variable "delivery_bucket_name" {
  description = "Central S3 bucket (in the security account) configuration snapshots and history are delivered to."
  type        = string
}

variable "delivery_key_prefix" {
  description = "Prefix inside the central bucket. Defaults to the account ID."
  type        = string
  default     = null
}

variable "delivery_frequency" {
  description = "How often configuration snapshots are delivered."
  type        = string
  default     = "TwentyFour_Hours"

  validation {
    condition = contains(
      ["One_Hour", "Three_Hours", "Six_Hours", "Twelve_Hours", "TwentyFour_Hours"],
      var.delivery_frequency,
    )
    error_message = "Invalid delivery frequency."
  }
}

variable "record_all_supported_resources" {
  description = "Record every supported resource type. Set to false to record only var.resource_types (cheaper, but blinds other rules)."
  type        = bool
  default     = true
}

variable "resource_types" {
  description = "Resource types to record when record_all_supported_resources is false."
  type        = list(string)
  default = [
    "AWS::S3::Bucket",
    "AWS::RDS::DBInstance",
    "AWS::RDS::DBCluster",
    "AWS::RDS::DBSnapshot",
    "AWS::RDS::DBClusterSnapshot",
    "AWS::DynamoDB::Table",
    "AWS::KMS::Key",
    "AWS::EC2::Volume",
  ]
}

variable "include_global_resource_types" {
  description = "Record global resources (IAM). Enable in exactly one region per account."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to created resources."
  type        = map(string)
  default     = {}
}
