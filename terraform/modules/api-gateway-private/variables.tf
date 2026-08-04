variable "name" {
  description = "Name of the private REST API and associated resources."
  type        = string
}

variable "description" {
  description = "Human-readable description of the API."
  type        = string
  default     = "Private API Gateway managed by Terraform"
}

variable "stage_name" {
  description = "API Gateway stage name."
  type        = string
  default     = "v1"
}

variable "vpc_id" {
  description = "ID of the VPC where the execute-api VPC Interface Endpoint is created."
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs (private, one per AZ) for the VPC Interface Endpoint ENIs."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "At least one subnet ID is required."
  }
}

variable "vpc_cidr_blocks" {
  description = "VPC CIDR blocks allowed to reach the endpoint on port 443."
  type        = list(string)

  validation {
    condition     = length(var.vpc_cidr_blocks) > 0
    error_message = "At least one VPC CIDR block is required."
  }
}

variable "private_hosted_zone_id" {
  description = "Route 53 private hosted zone ID. When set, a DNS record is created for var.private_dns_name."
  type        = string
  default     = null
}

variable "private_dns_name" {
  description = "DNS name to create inside the private hosted zone (e.g. internal-api.allianz-trade.com)."
  type        = string
  default     = null
}

variable "log_retention_in_days" {
  description = "Retention period for the CloudWatch access log group."
  type        = number
  default     = 365
}

variable "tags" {
  description = "Tags applied to all resources in this module."
  type        = map(string)
  default     = {}
}
