variable "name" {
  description = "Prefix applied to every resource created by this root module."
  type        = string
  default     = "allianz-trade-api"
}

variable "region" {
  description = "Primary AWS region."
  type        = string
  default     = "eu-central-1"
}

variable "terraform_execution_role_arn" {
  description = "IAM role Terraform assumes to manage resources."
  type        = string
}

# ---------------------------------------------------------------------------
# Public APIs
# ---------------------------------------------------------------------------
variable "public_apis" {
  description = <<-EOT
    Map of team name -> public API configuration.
    Each entry produces one Regional API Gateway + one regional WAF web ACL.
  EOT
  type = map(object({
    description           = string
    stage_name            = string
    origin_verify_secret  = string
    custom_domain_name    = optional(string)
    acm_certificate_arn   = optional(string)
    base_path             = optional(string, "")
    rate_limit            = optional(number)
  }))

  validation {
    condition     = length(var.public_apis) > 0
    error_message = "At least one public API must be defined."
  }
}

# ---------------------------------------------------------------------------
# Private APIs
# ---------------------------------------------------------------------------
variable "private_apis" {
  description = "Map of team name -> private API configuration. Each entry produces a Private API Gateway + VPC endpoint."
  type = map(object({
    description            = string
    stage_name             = string
    vpc_id                 = string
    subnet_ids             = list(string)
    vpc_cidr_blocks        = list(string)
    private_hosted_zone_id = optional(string)
    private_dns_name       = optional(string)
  }))
  default = {}
}

# ---------------------------------------------------------------------------
# CloudFront
# ---------------------------------------------------------------------------
variable "public_domain_name" {
  description = "Public domain name served by CloudFront (e.g. api.allianz-trade.com)."
  type        = string
}

variable "cloudfront_acm_certificate_arn" {
  description = "ARN of the ACM certificate in us-east-1 for the public domain."
  type        = string
}

variable "cloudfront_price_class" {
  description = "CloudFront price class."
  type        = string
  default     = "PriceClass_100"
}

variable "cloudfront_origin_shield_region" {
  description = "Enable CloudFront Origin Shield in this region. Null disables it."
  type        = string
  default     = null
}

variable "cloudfront_default_origin_id" {
  description = "Key in var.public_apis to use as the default CloudFront origin."
  type        = string
}

variable "cloudfront_path_behaviors" {
  description = "Ordered path-based routing rules, each pointing to a team API origin."
  type = list(object({
    path_pattern             = string
    origin_id                = string
    cache_policy_id          = optional(string)
    origin_request_policy_id = optional(string)
  }))
  default = []
}

variable "cloudfront_access_log_bucket" {
  description = "S3 bucket domain name for CloudFront access logs. Null disables logging."
  type        = string
  default     = null
}

variable "public_hosted_zone_id" {
  description = "Route 53 public hosted zone ID for the public domain. When set, an alias record is created."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# WAF
# ---------------------------------------------------------------------------
variable "waf_cloudfront_rate_limit" {
  description = "Requests per 5 minutes per IP blocked by the CloudFront-scope WAF."
  type        = number
  default     = 5000
}

variable "waf_regional_rate_limit" {
  description = "Default requests per 5 minutes per IP blocked by each regional WAF."
  type        = number
  default     = 2000
}

variable "waf_blocked_countries" {
  description = "ISO 3166-1 alpha-2 country codes blocked by WAF."
  type        = list(string)
  default     = []
}

variable "waf_log_destination_arn" {
  description = "ARN of the S3 bucket or Kinesis Firehose for WAFv2 logs."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Observability
# ---------------------------------------------------------------------------
variable "log_retention_in_days" {
  description = "CloudWatch Logs retention for API Gateway access log groups."
  type        = number
  default     = 365
}

variable "waf_block_alarm_threshold" {
  description = "Number of WAF blocked requests per 5-minute period that triggers an alarm."
  type        = number
  default     = 500
}

variable "api_5xx_alarm_threshold" {
  description = "Number of 5XX errors per 5-minute period that triggers an alarm."
  type        = number
  default     = 50
}

variable "alarm_sns_topic_arns" {
  description = "SNS topic ARNs to notify when a CloudWatch alarm fires."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Common
# ---------------------------------------------------------------------------
variable "default_tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default = {
    Project   = "api-platform"
    ManagedBy = "terraform"
  }
}
