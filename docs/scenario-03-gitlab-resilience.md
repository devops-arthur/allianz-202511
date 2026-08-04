# Scenario 3 — GitLab Resilience & Monitoring

## Architecture

```
Internet
   │
   ▼
ALB (multi-AZ, HTTPS/TLS 1.3)
   │
   ▼
Auto Scaling Group  ──────────────────────────────────────────┐
  GitLab app (m6i.xlarge)  ×2–6 across private subnets        │
  IMDSv2 enforced                                              │
  SSM Session Manager (no SSH)                                 │
   │                                                           │
   ├── EFS (encrypted, multi-AZ)  ◄── git-data / uploads /    │
   │                                   artifacts               │
   └── RDS PostgreSQL 16 Multi-AZ ◄── gitlabhq_production     │
         automated backups (7d)                                │
         deletion protection ON                                │
                                                               │
CloudWatch Alarms ─────────────────────────────────────────────┘
  → SNS → email / Slack / PagerDuty
```

## Resilience decisions

| Concern | Solution |
|---|---|
| Single-AZ app failure | ASG spans all private subnets across AZs |
| EBS single-instance storage | Replaced with EFS — all nodes share one filesystem |
| Database failover | RDS Multi-AZ with automatic failover (<60 s) |
| Load spike | Target-tracking ASG policy at 70% CPU |
| Rolling deploys | Instance Refresh with 50% min-healthy |
| Secrets in userdata | `db_password` injected via `TF_VAR_db_password` from GitHub secret |

## Monitoring

| Alarm | Threshold | Action |
|---|---|---|
| RDS CPU | > 80% for 10 min | SNS alert |
| RDS free storage | < 10 GB | SNS alert |
| ALB 5xx errors | > 50 in 5 min | SNS alert |
| App server CPU | > 85% for 10 min | SNS alert |
| EFS burst credit | < 1 GB | SNS alert |

## Execution flow

```
git push → main
  │
  ├─ GitHub Actions: terraform-gitlab.yml
  │     │
  │     ├─ OIDC token → cicd-bootstrap (arn:aws:iam::247338422836:role/cicd-bootstrap)
  │     ├─ role-chaining → terraform-execution
  │     └─ terraform init → validate → plan → apply
  │
  └─ Resources created/updated:
        SNS topic + email subscription
        Security groups (ALB / app / EFS / RDS)
        EFS file system + mount targets (one per AZ)
        RDS PostgreSQL Multi-AZ
        ALB + target group + HTTPS listener
        Launch template (IMDSv2, EFS mount, GitLab config)
        Auto Scaling Group + target-tracking policy
        CloudWatch alarms (5 alarms)
```

## Runbook — common incidents

### ALB 5xx spike

1. Check ASG instance health: `aws autoscaling describe-auto-scaling-instances`
2. Review GitLab logs via SSM: `aws ssm start-session --target <instance-id>`
3. If a bad deploy: trigger instance refresh to roll back AMI

### RDS failover

RDS Multi-AZ promotes the standby automatically. GitLab reconnects via the
endpoint DNS (no IP change required). Verify with:

```bash
aws rds describe-db-instances \
  --db-instance-identifier gitlab-postgres \
  --query 'DBInstances[0].MultiAZ'
```

### EFS burst credit exhaustion

Switch throughput mode to `provisioned` by updating `var.efs_throughput_mode`
and re-applying. No data loss or remount required.

### Scale-out not triggering

Verify the ASG target-tracking policy is active:

```bash
aws autoscaling describe-policies --auto-scaling-group-name gitlab-asg
```
