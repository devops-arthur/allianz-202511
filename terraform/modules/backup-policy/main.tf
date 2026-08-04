data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  partition  = data.aws_partition.current.partition
  account_id = data.aws_caller_identity.current.account_id
}

# ── IAM role AWS Backup uses to perform backup/restore operations ─────────────

data "aws_iam_policy_document" "backup_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backup" {
  name               = "${var.name}-backup-role"
  assume_role_policy = data.aws_iam_policy_document.backup_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "restore" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

# ── Backup vault with WORM (Vault Lock) ───────────────────────────────────────

resource "aws_backup_vault" "main" {
  name        = "${var.name}-vault"
  kms_key_arn = var.kms_key_arn
  tags = merge(var.tags, {
    Owner = var.owner_tag
  })
}

resource "aws_backup_vault_lock_configuration" "main" {
  backup_vault_name   = aws_backup_vault.main.name
  min_retention_days  = var.vault_lock_min_retention_days
  max_retention_days  = var.vault_lock_max_retention_days
  # changeable_for_days omitted — lock is applied immediately (compliance mode)
}

# ── Backup plan ───────────────────────────────────────────────────────────────

resource "aws_backup_plan" "main" {
  name = "${var.name}-plan"
  tags = var.tags

  # Daily backups — short retention, fast recovery
  rule {
    rule_name         = "daily"
    target_vault_name = aws_backup_vault.main.name
    schedule          = var.daily_schedule
    start_window      = 60
    completion_window = 180

    lifecycle {
      delete_after = var.daily_delete_after_days
    }

    dynamic "copy_action" {
      for_each = var.copy_to_region != null ? [1] : []
      content {
        destination_vault_arn = var.copy_vault_arn
        lifecycle { delete_after = var.copy_delete_after_days }
      }
    }

    dynamic "copy_action" {
      for_each = var.cross_account_vault_arn != null ? [1] : []
      content {
        destination_vault_arn = var.cross_account_vault_arn
        lifecycle { delete_after = var.cross_account_delete_after_days }
      }
    }
  }

  # Monthly backups — long retention for compliance and point-in-time recovery
  rule {
    rule_name         = "monthly"
    target_vault_name = aws_backup_vault.main.name
    schedule          = var.monthly_schedule
    start_window      = 60
    completion_window = 360

    lifecycle {
      delete_after = var.monthly_delete_after_days
    }

    dynamic "copy_action" {
      for_each = var.copy_to_region != null ? [1] : []
      content {
        destination_vault_arn = var.copy_vault_arn
        lifecycle { delete_after = var.copy_delete_after_days }
      }
    }

    dynamic "copy_action" {
      for_each = var.cross_account_vault_arn != null ? [1] : []
      content {
        destination_vault_arn = var.cross_account_vault_arn
        lifecycle { delete_after = var.cross_account_delete_after_days }
      }
    }
  }
}

# ── Resource selection — tag-based ────────────────────────────────────────────

resource "aws_backup_selection" "tagged" {
  name         = "${var.name}-tagged-resources"
  plan_id      = aws_backup_plan.main.id
  iam_role_arn = aws_iam_role.backup.arn

  selection_tag {
    type  = "STRINGEQUALS"
    key   = var.backup_tag_key
    value = var.backup_tag_value
  }
}

# ── CloudWatch alarm — failed backup jobs ─────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "failed_jobs" {
  alarm_name          = "${var.name}-backup-failed-jobs"
  alarm_description   = "One or more AWS Backup jobs failed in the last hour"
  namespace           = "AWS/Backup"
  metric_name         = "NumberOfBackupJobsFailed"
  statistic           = "Sum"
  period              = 3600
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  tags                = var.tags
}
