variable "name" {
  description = "Name of the WAFv2 web ACL."
  type        = string
}

variable "description" {
  description = "Human-readable description."
  type        = string
  default     = "WAFv2 web ACL managed by Terraform"
}

variable "scope" {
  description = "CLOUDFRONT (must deploy in us-east-1) or REGIONAL (same region as the protected resource)."
  type        = string

  validation {
    condition     = contains(["CLOUDFRONT", "REGIONAL"], var.scope)
    error_message = "scope must be CLOUDFRONT or REGIONAL."
  }
}

variable "default_action" {
  description = "Default action when no rule matches: allow or block."
  type        = string
  default     = "allow"

  validation {
    condition     = contains(["allow", "block"], var.default_action)
    error_message = "default_action must be allow or block."
  }
}

variable "enable_core_rule_set" {
  description = "Attach the AWS Managed Rules Common Rule Set (OWASP Top 10 coverage)."
  type        = bool
  default     = true
}

variable "core_rule_set_overrides" {
  description = "Override individual CRS rule actions. Map of rule name -> 'count' or 'allow'."
  type        = map(string)
  default     = {}
}

variable "enable_known_bad_inputs" {
  description = "Attach the AWS Managed Rules Known Bad Inputs rule set."
  type        = bool
  default     = true
}

variable "enable_ip_reputation" {
  description = "Attach the AWS Managed Rules Amazon IP Reputation List."
  type        = bool
  default     = true
}

variable "rate_limit" {
  description = "Requests per 5 minutes per IP above which the request is blocked. 0 disables rate limiting."
  type        = number
  default     = 2000
}

variable "blocked_countries" {
  description = "ISO 3166-1 alpha-2 country codes to block. Empty list disables geo-blocking."
  type        = list(string)
  default     = []
}

variable "log_destination_arn" {
  description = "ARN of an S3 bucket or Kinesis Firehose stream to deliver WAF logs to. Null disables logging."
  type        = string
  default     = null
}

variable "log_filter_default_behavior" {
  description = "When set (KEEP or DROP), enables a logging filter that always keeps BLOCK decisions. Null means log everything."
  type        = string
  default     = "DROP"

  validation {
    condition     = var.log_filter_default_behavior == null || contains(["KEEP", "DROP"], var.log_filter_default_behavior)
    error_message = "log_filter_default_behavior must be KEEP, DROP, or null."
  }
}

variable "tags" {
  description = "Tags applied to the web ACL."
  type        = map(string)
  default     = {}
}
