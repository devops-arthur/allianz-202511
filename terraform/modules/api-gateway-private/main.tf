data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
  partition  = data.aws_partition.current.partition
}

# ---------------------------------------------------------------------------
# VPC Interface Endpoint for execute-api
# All internal API traffic enters via this endpoint — no internet path exists.
# ---------------------------------------------------------------------------
resource "aws_vpc_endpoint" "execute_api" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${local.region}.execute-api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true

  tags = merge(var.tags, { Name = "${var.name}-execute-api-vpce" })
}

# Security group: allow HTTPS only from the VPC CIDR block(s).
resource "aws_security_group" "vpce" {
  name        = "${var.name}-execute-api-vpce"
  description = "Allow HTTPS traffic from the VPC to the execute-api VPC endpoint"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.vpc_cidr_blocks
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-execute-api-vpce" })
}

# ---------------------------------------------------------------------------
# Private API Gateway
# ---------------------------------------------------------------------------
resource "aws_api_gateway_rest_api" "this" {
  name        = var.name
  description = var.description

  endpoint_configuration {
    types            = ["PRIVATE"]
    vpc_endpoint_ids = [aws_vpc_endpoint.execute_api.id]
  }

  tags = var.tags
}

# Resource policy: allow only requests arriving via the VPC endpoint;
# deny everything else, including direct calls to the execute-api hostname.
data "aws_iam_policy_document" "resource_policy" {
  statement {
    sid    = "AllowVpcEndpointOnly"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions   = ["execute-api:Invoke"]
    resources = ["arn:${local.partition}:execute-api:${local.region}:${local.account_id}:${aws_api_gateway_rest_api.this.id}/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceVpce"
      values   = [aws_vpc_endpoint.execute_api.id]
    }
  }

  statement {
    sid    = "DenyAllOtherSources"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions   = ["execute-api:Invoke"]
    resources = ["arn:${local.partition}:execute-api:${local.region}:${local.account_id}:${aws_api_gateway_rest_api.this.id}/*"]

    condition {
      test     = "StringNotEquals"
      variable = "aws:SourceVpce"
      values   = [aws_vpc_endpoint.execute_api.id]
    }
  }
}

resource "aws_api_gateway_rest_api_policy" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  policy      = data.aws_iam_policy_document.resource_policy.json
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
# CloudWatch Logs
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "access_logs" {
  name              = "/aws/api-gateway/${var.name}/${var.stage_name}"
  retention_in_days = var.log_retention_in_days
  tags              = var.tags
}

# ---------------------------------------------------------------------------
# Route 53 private hosted zone record (optional)
# Resolves internal-api.allianz-trade.com inside the VPC.
# ---------------------------------------------------------------------------
resource "aws_route53_record" "this" {
  count = var.private_hosted_zone_id != null ? 1 : 0

  zone_id = var.private_hosted_zone_id
  name    = var.private_dns_name
  type    = "A"

  alias {
    name                   = aws_vpc_endpoint.execute_api.dns_entry[0]["dns_name"]
    zone_id                = aws_vpc_endpoint.execute_api.dns_entry[0]["hosted_zone_id"]
    evaluate_target_health = true
  }
}
