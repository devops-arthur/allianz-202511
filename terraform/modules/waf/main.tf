data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
}

# ---------------------------------------------------------------------------
# WAFv2 Web ACL
# scope = CLOUDFRONT  -> must be deployed in us-east-1 (use provider alias)
# scope = REGIONAL    -> deployed in the same region as the API Gateway / ALB
# ---------------------------------------------------------------------------
resource "aws_wafv2_web_acl" "this" {
  name        = var.name
  description = var.description
  scope       = var.scope

  default_action {
    dynamic "allow" {
      for_each = var.default_action == "allow" ? [1] : []
      content {}
    }

    dynamic "block" {
      for_each = var.default_action == "block" ? [1] : []
      content {}
    }
  }

  # --- AWS Managed Rule Groups -----------------------------------------------

  dynamic "rule" {
    for_each = var.enable_core_rule_set ? [1] : []

    content {
      name     = "AWSManagedRulesCommonRuleSet"
      priority = 10

      override_action { none {} }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesCommonRuleSet"
          vendor_name = "AWS"

          dynamic "rule_action_override" {
            for_each = var.core_rule_set_overrides

            content {
              name = rule_action_override.key
              action_to_use {
                dynamic "count" {
                  for_each = rule_action_override.value == "count" ? [1] : []
                  content {}
                }
                dynamic "allow" {
                  for_each = rule_action_override.value == "allow" ? [1] : []
                  content {}
                }
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name}-core-rule-set"
        sampled_requests_enabled   = true
      }
    }
  }

  dynamic "rule" {
    for_each = var.enable_known_bad_inputs ? [1] : []

    content {
      name     = "AWSManagedRulesKnownBadInputsRuleSet"
      priority = 20

      override_action { none {} }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesKnownBadInputsRuleSet"
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name}-known-bad-inputs"
        sampled_requests_enabled   = true
      }
    }
  }

  dynamic "rule" {
    for_each = var.enable_ip_reputation ? [1] : []

    content {
      name     = "AWSManagedRulesAmazonIpReputationList"
      priority = 30

      override_action { none {} }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesAmazonIpReputationList"
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name}-ip-reputation"
        sampled_requests_enabled   = true
      }
    }
  }

  # --- Rate Limiting ----------------------------------------------------------

  dynamic "rule" {
    for_each = var.rate_limit > 0 ? [1] : []

    content {
      name     = "${var.name}-rate-limit"
      priority = 40

      action { block {} }

      statement {
        rate_based_statement {
          limit              = var.rate_limit
          aggregate_key_type = "IP"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name}-rate-limit"
        sampled_requests_enabled   = true
      }
    }
  }

  # --- Geo-blocking -----------------------------------------------------------

  dynamic "rule" {
    for_each = length(var.blocked_countries) > 0 ? [1] : []

    content {
      name     = "${var.name}-geo-block"
      priority = 50

      action { block {} }

      statement {
        geo_match_statement {
          country_codes = var.blocked_countries
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name}-geo-block"
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = var.name
    sampled_requests_enabled   = true
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# WAFv2 logging to S3 (optional)
# ---------------------------------------------------------------------------
resource "aws_wafv2_web_acl_logging_configuration" "this" {
  count = var.log_destination_arn != null ? 1 : 0

  log_destination_configs = [var.log_destination_arn]
  resource_arn            = aws_wafv2_web_acl.this.arn

  dynamic "logging_filter" {
    for_each = var.log_filter_default_behavior != null ? [1] : []

    content {
      default_behavior = var.log_filter_default_behavior

      filter {
        behavior = "KEEP"
        condition {
          action_condition { action = "BLOCK" }
        }
        requirement = "MEETS_ANY"
      }
    }
  }
}
