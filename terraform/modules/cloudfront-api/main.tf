data "aws_acm_certificate" "this" {
  count = var.acm_certificate_arn == null ? 0 : 0 # resolved via var directly

  domain      = var.domain_name
  statuses    = ["ISSUED"]
  most_recent = true
}

# ---------------------------------------------------------------------------
# CloudFront distribution
# One origin per API team; path-based behaviours route traffic to the right
# Regional API Gateway custom domain.
# ---------------------------------------------------------------------------
resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = var.comment
  price_class         = var.price_class
  aliases             = [var.domain_name]
  web_acl_id          = var.web_acl_arn
  http_version        = "http2and3"
  wait_for_deployment = false

  # ---------------------------------------------------------------------------
  # Origins — one per team API (Regional API GW custom domain or invoke URL)
  # ---------------------------------------------------------------------------
  dynamic "origin" {
    for_each = var.api_origins

    content {
      origin_id   = origin.key
      domain_name = origin.value.domain_name

      custom_origin_config {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "https-only"
        origin_ssl_protocols   = ["TLSv1.2"]

        # Keep-alive and read timeouts (seconds)
        origin_keepalive_timeout = 60
        origin_read_timeout      = 30
      }

      # Origin-verify secret — prevents direct access to the Regional API GW endpoint.
      custom_header {
        name  = "x-origin-verify"
        value = origin.value.origin_verify_secret
      }

      dynamic "origin_shield" {
        for_each = var.origin_shield_region != null ? [1] : []

        content {
          enabled              = true
          origin_shield_region = var.origin_shield_region
        }
      }
    }
  }

  # ---------------------------------------------------------------------------
  # Default cache behaviour — routes to the default (first) origin
  # ---------------------------------------------------------------------------
  default_cache_behavior {
    target_origin_id       = var.default_origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id          = var.cache_policy_id
    origin_request_policy_id = var.origin_request_policy_id

    dynamic "function_association" {
      for_each = var.viewer_request_function_arn != null ? [1] : []

      content {
        event_type   = "viewer-request"
        function_arn = var.viewer_request_function_arn
      }
    }
  }

  # ---------------------------------------------------------------------------
  # Path-based ordered behaviours — route by path prefix to team origins
  # ---------------------------------------------------------------------------
  dynamic "ordered_cache_behavior" {
    for_each = var.path_behaviors

    content {
      path_pattern           = ordered_cache_behavior.value.path_pattern
      target_origin_id       = ordered_cache_behavior.value.origin_id
      viewer_protocol_policy = "redirect-to-https"
      allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
      cached_methods         = ["GET", "HEAD"]
      compress               = true

      cache_policy_id          = coalesce(ordered_cache_behavior.value.cache_policy_id, var.cache_policy_id)
      origin_request_policy_id = coalesce(ordered_cache_behavior.value.origin_request_policy_id, var.origin_request_policy_id)
    }
  }

  # ---------------------------------------------------------------------------
  # TLS
  # ---------------------------------------------------------------------------
  viewer_certificate {
    acm_certificate_arn      = var.acm_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  # ---------------------------------------------------------------------------
  # Geo-restriction (pass-through to WAF by default)
  # ---------------------------------------------------------------------------
  restrictions {
    geo_restriction {
      restriction_type = length(var.geo_restriction_locations) > 0 ? var.geo_restriction_type : "none"
      locations        = var.geo_restriction_locations
    }
  }

  # ---------------------------------------------------------------------------
  # Logging
  # ---------------------------------------------------------------------------
  dynamic "logging_config" {
    for_each = var.access_log_bucket != null ? [1] : []

    content {
      bucket          = var.access_log_bucket
      prefix          = "cloudfront/${var.domain_name}/"
      include_cookies = false
    }
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Route 53 alias record
# ---------------------------------------------------------------------------
resource "aws_route53_record" "this" {
  count = var.hosted_zone_id != null ? 1 : 0

  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}
