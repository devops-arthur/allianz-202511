data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

locals {
  partition  = data.aws_partition.current.partition
  account_id = data.aws_caller_identity.current.account_id

  # Collect origin-verify secrets per team for CloudFront origin headers.
  api_origins = {
    for team, cfg in var.public_apis :
    team => {
      domain_name          = module.public_api[team].custom_domain_regional_domain_name != null ? module.public_api[team].custom_domain_regional_domain_name : "${module.public_api[team].api_id}.execute-api.${var.region}.amazonaws.com"
      origin_verify_secret = cfg.origin_verify_secret
    }
  }
}

# ---------------------------------------------------------------------------
# WAF — CloudFront scope (must live in us-east-1)
# ---------------------------------------------------------------------------
module "waf_cloudfront" {
  source = "../../modules/waf"

  providers = { aws = aws.us_east_1 }

  name                    = "${var.name}-cloudfront"
  scope                   = "CLOUDFRONT"
  rate_limit              = var.waf_cloudfront_rate_limit
  blocked_countries       = var.waf_blocked_countries
  log_destination_arn     = var.waf_log_destination_arn
  enable_core_rule_set    = true
  enable_known_bad_inputs = true
  enable_ip_reputation    = true

  tags = { Component = "waf-cloudfront" }
}

# ---------------------------------------------------------------------------
# WAF — Regional scope (per-API Gateway, secondary defence-in-depth)
# ---------------------------------------------------------------------------
module "waf_regional" {
  source   = "../../modules/waf"
  for_each = var.public_apis

  name                    = "${var.name}-${each.key}-regional"
  scope                   = "REGIONAL"
  rate_limit              = lookup(each.value, "rate_limit", var.waf_regional_rate_limit)
  blocked_countries       = var.waf_blocked_countries
  log_destination_arn     = var.waf_log_destination_arn
  enable_core_rule_set    = true
  enable_known_bad_inputs = true
  enable_ip_reputation    = true

  tags = { Component = "waf-regional", Team = each.key }
}

# ---------------------------------------------------------------------------
# Public (Regional) API Gateways — one per team
# ---------------------------------------------------------------------------
module "public_api" {
  source   = "../../modules/api-gateway-public"
  for_each = var.public_apis

  name                       = "${var.name}-${each.key}"
  description                = each.value.description
  stage_name                 = each.value.stage_name
  origin_verify_secret_value = each.value.origin_verify_secret
  regional_web_acl_arn       = module.waf_regional[each.key].web_acl_arn
  custom_domain_name         = lookup(each.value, "custom_domain_name", null)
  acm_certificate_arn        = lookup(each.value, "acm_certificate_arn", null)
  base_path                  = lookup(each.value, "base_path", "")
  log_retention_in_days      = var.log_retention_in_days

  tags = { Component = "api-gateway-public", Team = each.key }
}

# ---------------------------------------------------------------------------
# CloudFront distribution — path-based routing to team API Gateways
# ---------------------------------------------------------------------------
module "cloudfront" {
  source = "../../modules/cloudfront-api"

  domain_name         = var.public_domain_name
  comment             = "Allianz-Trade public API platform — managed by Terraform"
  acm_certificate_arn = var.cloudfront_acm_certificate_arn
  web_acl_arn         = module.waf_cloudfront.web_acl_arn
  price_class         = var.cloudfront_price_class
  origin_shield_region = var.cloudfront_origin_shield_region
  hosted_zone_id      = var.public_hosted_zone_id
  access_log_bucket   = var.cloudfront_access_log_bucket

  api_origins       = local.api_origins
  default_origin_id = var.cloudfront_default_origin_id
  path_behaviors    = var.cloudfront_path_behaviors

  tags = { Component = "cloudfront" }

  depends_on = [module.public_api]
}

# ---------------------------------------------------------------------------
# Private API Gateways — one per internal API, VPC-only
# ---------------------------------------------------------------------------
module "private_api" {
  source   = "../../modules/api-gateway-private"
  for_each = var.private_apis

  name                   = "${var.name}-${each.key}-internal"
  description            = each.value.description
  stage_name             = each.value.stage_name
  vpc_id                 = each.value.vpc_id
  subnet_ids             = each.value.subnet_ids
  vpc_cidr_blocks        = each.value.vpc_cidr_blocks
  private_hosted_zone_id = lookup(each.value, "private_hosted_zone_id", null)
  private_dns_name       = lookup(each.value, "private_dns_name", null)
  log_retention_in_days  = var.log_retention_in_days

  tags = { Component = "api-gateway-private", Team = each.key }
}

# ---------------------------------------------------------------------------
# CloudWatch alarms — error rate and WAF block rate monitoring
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "waf_block_rate" {
  for_each = var.public_apis

  alarm_name          = "${var.name}-${each.key}-waf-block-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "BlockedRequests"
  namespace           = "AWS/WAFV2"
  period              = 300
  statistic           = "Sum"
  threshold           = var.waf_block_alarm_threshold
  alarm_description   = "WAF is blocking an elevated number of requests to the ${each.key} API"
  alarm_actions       = var.alarm_sns_topic_arns
  treat_missing_data  = "notBreaching"

  dimensions = {
    WebACL = module.waf_regional[each.key].web_acl_name
    Region = var.region
    Rule   = "ALL"
  }

  tags = { Team = each.key }
}

resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  for_each = var.public_apis

  alarm_name          = "${var.name}-${each.key}-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = 300
  statistic           = "Sum"
  threshold           = var.api_5xx_alarm_threshold
  alarm_description   = "5XX error rate elevated on the ${each.key} API"
  alarm_actions       = var.alarm_sns_topic_arns
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiName = "${var.name}-${each.key}"
    Stage   = each.value.stage_name
  }

  tags = { Team = each.key }
}
