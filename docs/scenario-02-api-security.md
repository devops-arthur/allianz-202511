# Scenario #2 — API Architecture & Security for Allianz-Trade on AWS

## 1. Context & Problem Statement

Allianz-Trade exposes all APIs — both public and internal — through a single public endpoint
(`api.allianz-trade.com`). Backend services are Lambda functions or ECS Fargate microservices
behind internal ALBs. A global AWS WAFv2 + Shield Advanced protect the edge, but several
structural weaknesses were identified:

| # | Weakness | Risk |
|---|---|---|
| 1 | Internal APIs reachable from the public internet | Unnecessary attack surface; data exfiltration path |
| 2 | Single endpoint for all teams and API types | Broad blast radius; difficult per-team access control |
| 3 | Regional API Gateway endpoints accessible directly | WAF and CloudFront can be bypassed entirely |

---

## 2. Target Architecture

```
Internet
   │
   ▼
[CloudFront + Shield Advanced]  ◄── WAFv2 web ACL (CloudFront scope)
   │  (api.allianz-trade.com)
   │  path-based behaviours
   ├──/payments/* ──────────────► Regional API GW (payments team)
   ├──/claims/*   ──────────────► Regional API GW (claims team)
   └──/partners/* ──────────────► Regional API GW (partners team)
          │
          │  resource policy: deny if not from CloudFront
          │  WAFv2 web ACL (regional scope, secondary layer)
          ▼
   [Lambda / ECS Fargate — internal ALB — VPC-only]

Corporate Network / AWS VPC
   │
   ▼
[VPC Interface Endpoint — execute-api]
   │
   ▼
[Private API Gateway]   ◄── resource policy: allow only from VPC endpoint
   │  (internal-api.allianz-trade.com — private DNS)
   ▼
[Lambda / ECS Fargate — internal ALB — VPC-only]
```

---

## 3. Implementation Plan

### Phase 1 — Harden Existing Public APIs

**Goal:** Ensure 100 % of public API traffic flows through CloudFront + WAF. No request should
reach API Gateway directly.

Steps:
1. Add a **resource policy** to every Regional API Gateway that denies all callers unless the
   request carries a secret header (`x-origin-verify`) set only by CloudFront.
2. Store the secret in **AWS Secrets Manager**; rotate it quarterly.  CloudFront injects it as a
   custom origin header; a Lambda@Edge function at the viewer-request stage validates it before
   forwarding.
3. Attach a **WAFv2 regional web ACL** directly to each API Gateway as a secondary defence layer
   (OWASP Core Rule Set + rate limiting).
4. Enable **CloudFront Origin Shield** in the primary region to reduce direct-origin probing.

Terraform resources:
- `aws_api_gateway_rest_api_policy` — resource policy per API
- `aws_wafv2_web_acl` (scope = `REGIONAL`) — per-API secondary WAF
- `aws_cloudfront_distribution` — with custom origin header
- `aws_secretsmanager_secret` — origin-verify secret

---

### Phase 2 — Migrate Internal APIs to Private API Gateway

**Goal:** Remove internal APIs from the public internet entirely.

Steps:
1. Create a **VPC Interface Endpoint** for `execute-api` in every VPC that needs internal API access.
2. Deploy **Private API Gateways** for every internal API (type = `PRIVATE`).
3. Attach a resource policy that **allows only requests arriving via the VPC endpoint** and
   **denies everything else** (including direct HTTPS calls).
4. Update internal service discovery (Route 53 Private Hosted Zone) to resolve
   `internal-api.allianz-trade.com` to the VPC endpoint DNS name.
5. Decommission public exposure of the migrated APIs.

Terraform resources:
- `aws_vpc_endpoint` (service = `com.amazonaws.<region>.execute-api`)
- `aws_api_gateway_rest_api` (endpoint_configuration type = `PRIVATE`)
- `aws_api_gateway_rest_api_policy` — deny `*`, allow `aws:sourceVpce`
- `aws_route53_zone` (private) + `aws_route53_record`

---

### Phase 3 — Endpoint Segmentation (Path-Based Routing)

**Goal:** Isolate teams so a misconfiguration or incident in one API does not affect others.

Steps:
1. Implement **path-based cache behaviours** in the CloudFront distribution:
   - `/payments/*` → payments API Gateway custom domain
   - `/claims/*` → claims API Gateway custom domain
   - `/partners/*` → partners API Gateway custom domain
2. Each API Gateway gets its own **WAFv2 web ACL** so teams can tune rate limits and rules
   independently.
3. Each API Gateway uses its own **API Gateway custom domain name** with an ACM certificate,
   enabling independent deployment lifecycles.

---

### Phase 4 — Authentication & Authorization Uplift

**Goal:** Every API call is authenticated; internal service-to-service calls never cross the internet.

| Consumer type | Auth mechanism |
|---|---|
| External clients (B2B partners) | Amazon Cognito User Pool — JWT authorizer on API Gateway |
| Internal services (VPC-to-VPC) | IAM auth (`AWS_IAM` authorizer) via VPC endpoint — no bearer token on wire |
| Legacy APIs (migration period) | Lambda authorizer — validates custom token, falls back to Cognito |

Steps:
1. Create a **Cognito User Pool** with client credentials flow for machine-to-machine external consumers.
2. Attach a **JWT authorizer** to all public API Gateway routes.
3. Attach **AWS_IAM authorizer** to all private API Gateway routes; grant consuming roles
   `execute-api:Invoke` via IAM policy.
4. Deprecate API-key-only authentication within 90 days.

---

### Phase 5 — Observability & Threat Detection

**Goal:** Full visibility of API traffic; real-time alerting on anomalies.

| Signal | Source | Destination |
|---|---|---|
| API access logs (latency, status) | API Gateway Access Logs | CloudWatch Logs → central S3 (security account) |
| WAF block/allow decisions | WAFv2 Logs | S3 → Security Lake |
| Abnormal API patterns | GuardDuty (API activity findings) | Security Hub |
| 4xx/5xx spikes | CloudWatch Alarms | SNS → OpsCenter |
| End-to-end traces | AWS X-Ray | X-Ray console / CloudWatch ServiceLens |

Steps:
1. Enable **Access Logging** on every API Gateway stage; ship to CloudWatch Logs.
2. Enable **WAFv2 logging** to S3 (central security account bucket).
3. Enable **GuardDuty** in all workload accounts; aggregate findings to Security Hub.
4. Create **CloudWatch Alarms** on `4XXError`, `5XXError`, WAF `BlockedRequests` metrics.
5. Enable **X-Ray active tracing** on all Lambda functions and API Gateway stages.

---

## 4. AWS Services Summary

| Layer | Service | Scope |
|---|---|---|
| DDoS / Edge | CloudFront + Shield Advanced | Global |
| WAF (primary) | WAFv2 web ACL — CloudFront scope | Global |
| WAF (secondary) | WAFv2 web ACL — Regional scope | Per API Gateway |
| Public APIs | Regional API Gateway + Custom Domain + ACM | Per team |
| Internal APIs | Private API Gateway + VPC Interface Endpoint | Per VPC |
| Auth (external) | Amazon Cognito + JWT Authorizer | Per public API |
| Auth (internal) | IAM (`AWS_IAM`) Authorizer | Per private API |
| Auth (legacy) | Lambda Authorizer | Per legacy API |
| Backend (serverless) | Lambda (VPC-attached) | Per microservice |
| Backend (container) | ECS Fargate + internal ALB | Per microservice |
| Secret rotation | Secrets Manager (origin-verify header) | Per CloudFront origin |
| Observability | CloudWatch, X-Ray, GuardDuty, Security Hub | All accounts |
| Logs centralisation | S3 (security account) + Security Lake | Cross-account |

---

## 5. Terraform Module Structure

```
terraform/
├── modules/
│   ├── waf/                    # WAFv2 web ACL (CloudFront or regional)
│   ├── cloudfront-api/         # CloudFront distribution with path-based routing
│   ├── api-gateway-public/     # Regional API Gateway locked to CloudFront
│   └── api-gateway-private/    # Private API Gateway + VPC endpoint
└── live/
    └── api-platform/           # Root module — wires all modules for Allianz-Trade
```

---

## 6. Security Controls Checklist

- [x] All public APIs reachable only via CloudFront (resource policy + origin-verify secret)
- [x] WAFv2 at CloudFront scope (OWASP CRS, rate limiting, geo-blocking)
- [x] WAFv2 at API Gateway scope (secondary / defence-in-depth)
- [x] Internal APIs exposed only via VPC endpoint (private API GW, no public URL)
- [x] JWT authorizer on all public API routes
- [x] IAM authorizer on all internal API routes
- [x] TLS 1.2+ enforced on CloudFront and API Gateway
- [x] API Gateway Access Logs enabled and centralised
- [x] WAFv2 logs enabled and shipped to security account
- [x] X-Ray tracing enabled end-to-end
- [x] GuardDuty enabled in all workload accounts
- [x] CloudWatch Alarms on error rate and WAF block rate
- [x] Origin-verify secret rotated quarterly via Secrets Manager rotation

---

## 7. Rollout Timeline

| Phase | Scope | Target |
|---|---|---|
| Phase 1 | Harden public APIs — origin lock + secondary WAF | Week 1–2 |
| Phase 2 | Migrate internal APIs to Private API Gateway | Week 3–5 |
| Phase 3 | CloudFront path segmentation per team | Week 4–6 |
| Phase 4 | Auth uplift — Cognito + IAM authorizers | Week 5–8 |
| Phase 5 | Observability — logs, alarms, GuardDuty | Week 7–9 |
