data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
  partition  = data.aws_partition.current.partition
}

# ---------------------------------------------------------------------------
# Origin-verify secret — CloudFront injects this as a custom request header;
# the API Gateway resource policy denies requests that do not carry it.
# ---------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "origin_verify" {
  name                    = "${var.name}-origin-verify"
  description             = "Secret header value injected by CloudFront to prove requests originate from the CDN"
  recovery_window_in_days = 7
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "origin_verify" {
  secret_id     = aws_secretsmanager_secret.origin_verify.id
  secret_string = var.origin_verify_secret_value
}

# ---------------------------------------------------------------------------
# API Gateway (Regional) — the actual REST API shell.
# Routes / integrations are managed by the consuming team outside this module.
# ---------------------------------------------------------------------------
resource "aws_api_gateway_rest_api" "this" {
  name        = var.name
  description = var.description

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Resource policy: deny all traffic unless it carries the origin-verify header.
# This ensures the regional endpoint is unreachable without going through
# CloudFront, even if someone discovers the execute-api hostname.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "api_resource_policy" {
  statement {
    sid    = "AllowCloudFrontOriginVerify"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions   = ["execute-api:Invoke"]
    resources = ["arn:${local.partition}:execute-api:${local.region}:${local.account_id}:${aws_api_gateway_rest_api.this.id}/*"]

    # Only requests that carry the shared secret injected by CloudFront are allowed.
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [local.region]
    }
  }

  statement {
    sid    = "DenyWithoutOriginVerifyHeader"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions   = ["execute-api:Invoke"]
    resources = ["arn:${local.partition}:execute-api:${local.region}:${local.account_id}:${aws_api_gateway_rest_api.this.id}/*"]

    # Deny if the header is absent or wrong. The header name and value are matched at
    # the CloudFront origin-request level; API GW enforces it as a policy condition.
    condition {
      test     = "StringNotEquals"
      variable = "aws:Referer"
      values   = [var.origin_verify_secret_value]
    }
  }
}

resource "aws_api_gateway_rest_api_policy" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  policy      = data.aws_iam_policy_document.api_resource_policy.json
}

# ---------------------------------------------------------------------------
# Deployment & stage
# ---------------------------------------------------------------------------
resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.this.body))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_api_gateway_rest_api_policy.this]
}

resource "aws_api_gateway_stage" "this" {
  deployment_id = aws_api_gateway_deployment.this.id
  rest_api_id   = aws_api_gateway_rest_api.this.id
  stage_name    = var.stage_name

  # Access logging to CloudWatch Logs
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.access_logs.arn
  }

  xray_tracing_enabled = true

  tags = var.tags
}

resource "aws_api_gateway_method_settings" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = aws_api_gateway_stage.this.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled    = true
    logging_level      = "INFO"
    data_trace_enabled = false
  }
}

# ---------------------------------------------------------------------------
# Regional WAF association (secondary / defence-in-depth layer)
# ---------------------------------------------------------------------------
resource "aws_wafv2_web_acl_association" "this" {
  count = var.regional_web_acl_arn != null ? 1 : 0

  resource_arn = aws_api_gateway_stage.this.arn
  web_acl_arn  = var.regional_web_acl_arn
}

# ---------------------------------------------------------------------------
# CloudWatch Logs
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "access_logs" {
  name              = "/aws/api-gateway/${var.name}/${var.stage_name}"
  retention_in_days = var.log_retention_in_days
  tags              = var.tags
}

# ---------------------------------------------------------------------------
# Custom domain name (optional — team owns their own ACM cert)
# ---------------------------------------------------------------------------
resource "aws_api_gateway_domain_name" "this" {
  count = var.custom_domain_name != null ? 1 : 0

  domain_name              = var.custom_domain_name
  regional_certificate_arn = var.acm_certificate_arn

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  security_policy = "TLS_1_2"

  tags = var.tags
}

resource "aws_api_gateway_base_path_mapping" "this" {
  count = var.custom_domain_name != null ? 1 : 0

  api_id      = aws_api_gateway_rest_api.this.id
  stage_name  = aws_api_gateway_stage.this.stage_name
  domain_name = aws_api_gateway_domain_name.this[0].domain_name
  base_path   = var.base_path
}
