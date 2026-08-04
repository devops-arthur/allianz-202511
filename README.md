# allianz-202511

Allianz-Trade AWS infrastructure — technical assessment covering four scenarios.

## Overview

| Scenario | Topic | Live Root | Module(s) |
|---|---|---|---|
| 1 | Encryption Management & BYOK Key Rotation | `live/security-keys` | `kms-external-key`, `rotation-compliance`, `config-baseline` |
| 2 | APIs-as-a-Product — Public & Private APIs | `live/api-platform` | `api-gateway-public`, `api-gateway-private`, `cloudfront-api`, `waf` |
| 3 | GitLab Resilience & Monitoring | `live/gitlab` | `gitlab-resilience` |
| 4 | Backup Policy with AWS Backup | `live/backup` | `backup-policy` |

All scenarios share a common IAM execution chain — no long-lived credentials anywhere.

---

## Repository Structure

```
.
├── .github/
│   └── workflows/
│       ├── terraform-iam-bootstrap.yml   # Scenario 0 — IAM roles bootstrap
│       ├── terraform-gitlab.yml          # Scenario 3 — GitLab infrastructure
│       └── terraform-backup.yml          # Scenario 4 — Backup policy
├── docs/
│   ├── scenario-02-api-security.md
│   └── scenario-03-gitlab-resilience.md
└── terraform/
    ├── modules/
    │   ├── kms-external-key/             # BYOK KMS key + key policy
    │   ├── rotation-compliance/          # AWS Config custom rule (Lambda)
    │   ├── config-baseline/              # AWS Config recorder + delivery channel
    │   ├── iam-terraform-role/           # OIDC-trusted Terraform execution role
    │   ├── api-gateway-public/           # Regional API GW locked to CloudFront
    │   ├── api-gateway-private/          # Private API GW + VPC endpoint
    │   ├── cloudfront-api/               # CloudFront with path-based routing
    │   ├── waf/                          # WAFv2 web ACL (CloudFront or regional)
    │   ├── gitlab-resilience/            # ALB + ASG + EFS + RDS Multi-AZ + alarms
    │   └── backup-policy/               # AWS Backup vault (WORM) + plan + selection
    └── live/
        ├── iam-bootstrap/               # Creates cicd-bootstrap + terraform-execution roles
        ├── security-keys/               # Scenario 1 — KMS BYOK keys per env/service
        ├── workload-accounts/           # Scenario 1 — Config baseline + rotation compliance
        ├── api-platform/                # Scenario 2 — Public + private API platform
        ├── gitlab/                      # Scenario 3 — GitLab resilience
        └── backup/                      # Scenario 4 — Backup policy per environment
```

---

## IAM Execution Chain (all scenarios)

No static AWS credentials are used anywhere. Every pipeline run follows this chain:

```
GitHub Actions runner
  │
  ├─ 1. GitHub OIDC token  (id-token: write)
  ├─ 2. Assumes cicd-bootstrap  →  sts:AssumeRole on terraform-execution only
  └─ 3. Chains into terraform-execution  →  runs terraform plan/apply
```

Bootstrap once per account:

```bash
# 1. Create OIDC provider
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1

# 2. Deploy cicd-bootstrap + terraform-execution via iam-bootstrap live root
cd terraform/live/iam-bootstrap
terraform init && terraform apply
```

---

## Scenario 1 — Encryption Management & BYOK Key Rotation

### Problem

Multiple environments (dev/int/prod) and services (S3, RDS, DynamoDB) each require dedicated
KMS keys with imported (BYOK/EXTERNAL) key material from an on-premises HSM. Rotating keys
without disrupting existing ciphertext is operationally complex.

### Solution

- One `aws_kms_external_key` per environment × service × generation. Keys are created in
  `PendingImport` state; material is imported out-of-band by a dedicated importer role.
- Rotation = bump `current_generation` in tfvars + re-point the service alias. Previous
  generations stay enabled for decryption of existing ciphertext.
- AWS Config custom rule (Lambda) in every workload account resolves `alias/<env>-<service>`
  to the current key ARN and flags any resource still using an older generation.

### Key policy split

| Statement | Who | What |
|---|---|---|
| KeyAdministration | `key_admin_role_arns` | Lifecycle management, no Encrypt/Decrypt |
| KeyMaterialCeremony | `key_material_importer_role_arns` | Import only |
| WorkloadCryptographicUse | Workload account root / explicit ARNs | Encrypt/Decrypt via service |
| BreakGlassDestructiveOperations | `break_glass_role_arns` | Delete material / schedule deletion |
| AuditReadOnly | `auditor_role_arns` | DescribeKey, ListGrants |

### Deploy

```bash
cd terraform/live/security-keys
cp terraform.tfvars.example terraform.tfvars   # fill in account IDs and role ARNs
terraform init && terraform apply

cd terraform/live/workload-accounts
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply
```

---

## Scenario 2 — APIs-as-a-Product

### Problem

All APIs (public and internal) share a single public endpoint. Regional API Gateway endpoints
are reachable directly, bypassing CloudFront and WAF.

### Solution

```
Internet
  │
  ▼
CloudFront + Shield Advanced  ◄── WAFv2 (CloudFront scope)
  │  path-based behaviours
  ├── /payments/*  ──► Regional API GW (payments)  ◄── WAFv2 (regional)
  ├── /claims/*    ──► Regional API GW (claims)     ◄── WAFv2 (regional)
  └── /partners/*  ──► Regional API GW (partners)   ◄── WAFv2 (regional)
         │  resource policy: deny unless x-origin-verify header present

Corporate VPC
  │
  ▼
VPC Interface Endpoint (execute-api)
  │
  ▼
Private API GW  ◄── resource policy: allow only from VPC endpoint
```

- Public APIs: locked to CloudFront via `x-origin-verify` secret header + resource policy.
- Private APIs: `PRIVATE` endpoint type, resource policy denies all except `aws:sourceVpce`.
- WAFv2: OWASP Core Rule Set + Known Bad Inputs + IP Reputation + rate limiting at both scopes.

### Deploy

```bash
cd terraform/live/api-platform
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply
```

---

## Scenario 3 — GitLab Resilience & Monitoring

### Problem

GitLab stores data on per-instance EBS volumes (single point of failure) and may not be
distributed across Availability Zones. Limited auto-scaling and monitoring.

### Solution

```
ALB (multi-AZ, HTTPS/TLS 1.3)
  │
Auto Scaling Group (2–6 × m6i.xlarge, private subnets, all AZs)
  │
  ├── EFS (encrypted, multi-AZ)  ←  git-data / uploads / artifacts
  └── RDS PostgreSQL 16 Multi-AZ ←  gitlabhq_production
```

- EBS replaced with EFS — all ASG nodes share one encrypted multi-AZ filesystem.
- RDS Multi-AZ with deletion protection, 7-day automated backups, point-in-time recovery.
- Target-tracking ASG policy at 70% CPU; rolling instance refresh (50% min-healthy).
- IMDSv2 enforced; SSH replaced by SSM Session Manager.
- CloudWatch alarms: RDS CPU, RDS free storage, ALB 5xx, app CPU, EFS burst credit.

### Deploy

```bash
cd terraform/live/gitlab
cp terraform.tfvars.example terraform.tfvars
TF_VAR_db_password=<secret> terraform init && terraform apply
```

---

## Scenario 4 — Backup Policy with AWS Backup

### Problem

No automated, scalable backup policy across dev/int/prod accounts. No WORM protection,
no cross-region or cross-account copies for disaster recovery.

### Solution

- One backup vault per account, encrypted with the account's KMS key, protected by
  **Vault Lock** (WORM — compliance mode, immutable once applied).
- Two backup rules per account:
  - Daily at 03:00 UTC — 35-day retention.
  - Monthly on the 1st at 05:00 UTC — 365-day retention.
- Both rules copy to a secondary region and a central DR account when configured.
- Resources opted in via tag `ToBackup=true`.
- CloudWatch alarm fires on any failed backup job.

### Vault Lock (WORM)

```hcl
resource "aws_backup_vault_lock_configuration" "main" {
  backup_vault_name  = aws_backup_vault.main.name
  min_retention_days = 30
  max_retention_days = 365
  # changeable_for_days omitted → compliance mode, lock is permanent
}
```

### Deploy

```bash
cd terraform/live/backup
cp terraform.tfvars.example terraform.tfvars   # fill in account IDs and KMS key ARNs
terraform init && terraform apply
```

Tag any resource to include it in backups:

```bash
aws resourcegroupstaggingapi tag-resources \
  --resource-arn-list <arn> \
  --tags ToBackup=true
```

---

## Region

All live roots default to `us-east-1`. Override per root via `terraform.tfvars`:

```hcl
region = "eu-central-1"
```

---

## CI/CD Pipelines

| Workflow | Trigger paths | Apply condition |
|---|---|---|
| `terraform-iam-bootstrap.yml` | `live/iam-bootstrap/**`, `modules/iam-terraform-role/**` | Push to `main` |
| `terraform-gitlab.yml` | `live/gitlab/**`, `modules/gitlab-resilience/**` | Push to `main` |
| `terraform-backup.yml` | `live/backup/**`, `modules/backup-policy/**` | Push to `main` |

All workflows use the same OIDC → `cicd-bootstrap` → `terraform-execution` chain.
No `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` secrets are used.

### Required GitHub repository secrets / variables

| Name | Type | Used by |
|---|---|---|
| `GITLAB_DB_PASSWORD` | Secret | `terraform-gitlab.yml` |

All role ARNs are hardcoded in the workflows using account `247338422836`.
Update them if deploying to a different account.
