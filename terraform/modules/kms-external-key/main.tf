data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  region     = data.aws_region.current.region
  partition  = data.aws_partition.current.partition
  account_id = data.aws_caller_identity.current.account_id

  key_name       = "${var.environment}-${var.service}"
  generation_tag = format("gen%d", var.generation)

  # Alias that identifies one immutable key generation. Never re-pointed.
  generation_alias = "alias/${local.key_name}-${local.generation_tag}"

  # Alias the workloads actually reference. Re-pointed on every rotation, which is what makes
  # rotation possible for keys that hold imported key material.
  service_alias = "alias/${local.key_name}"

  default_via_service = {
    s3       = ["s3.${local.region}.amazonaws.com"]
    rds      = ["rds.${local.region}.amazonaws.com"]
    ddb      = ["dynamodb.${local.region}.amazonaws.com"]
    dynamodb = ["dynamodb.${local.region}.amazonaws.com"]
  }

  via_service = length(var.via_service_principals) > 0 ? var.via_service_principals : lookup(local.default_via_service, var.service, [])

  # Grants are only created by the AWS services themselves (RDS, DynamoDB and S3 for some flows).
  needs_service_grants = contains(["rds", "ddb", "dynamodb"], var.service)

  tags = merge(
    var.tags,
    {
      Name           = local.key_name
      Environment    = var.environment
      Service        = var.service
      KeyGeneration  = tostring(var.generation)
      KeyOrigin      = "EXTERNAL"
      RotationMethod = "alias-repoint"
      ManagedBy      = "terraform"
    },
  )
}

# ---------------------------------------------------------------------------------------------------
# Key policy - least privilege, split between administration, usage, ceremony and audit.
# ---------------------------------------------------------------------------------------------------
data "aws_iam_policy_document" "key" {
  # 1. Lifecycle administration. Deliberately no Encrypt/Decrypt: a key admin must not be able to
  #    read data protected by the key.
  statement {
    sid    = "KeyAdministration"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = var.key_admin_role_arns
    }

    actions = [
      "kms:CancelKeyDeletion",
      "kms:CreateAlias",
      "kms:DeleteAlias",
      "kms:DescribeKey",
      "kms:DisableKey",
      "kms:EnableKey",
      "kms:GetKeyPolicy",
      "kms:GetKeyRotationStatus",
      "kms:ListAliases",
      "kms:ListGrants",
      "kms:ListKeyPolicies",
      "kms:ListResourceTags",
      "kms:PutKeyPolicy",
      "kms:ReplicateKey",
      "kms:RevokeGrant",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:UpdateAlias",
      "kms:UpdateKeyDescription",
    ]

    resources = ["*"]
  }

  # 2. Key material ceremony. Separated from administration so that importing material is a
  #    four-eyes operation performed by a dedicated role.
  dynamic "statement" {
    for_each = length(var.key_material_importer_role_arns) > 0 ? [1] : []

    content {
      sid    = "KeyMaterialCeremony"
      effect = "Allow"

      principals {
        type        = "AWS"
        identifiers = var.key_material_importer_role_arns
      }

      actions = [
        "kms:DescribeKey",
        "kms:GetParametersForImport",
        "kms:ImportKeyMaterial",
      ]

      resources = ["*"]
    }
  }

  # 3. Data-plane usage from the workload accounts, scoped to the owning AWS service.
  statement {
    sid    = "WorkloadCryptographicUse"
    effect = "Allow"

    principals {
      type = "AWS"
      identifiers = length(var.consumer_principal_arns) > 0 ? var.consumer_principal_arns : [
        for account_id in var.consumer_account_ids : "arn:${local.partition}:iam::${account_id}:root"
      ]
    }

    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey",
      "kms:GenerateDataKeyWithoutPlaintext",
      "kms:ReEncryptFrom",
      "kms:ReEncryptTo",
    ]

    resources = ["*"]

    # The key can only be used through the service it was created for ...
    dynamic "condition" {
      for_each = length(local.via_service) > 0 ? [1] : []

      content {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = local.via_service
      }
    }

    # ... and only on behalf of an approved account, even if a principal ARN is ever mistyped.
    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = var.consumer_account_ids
    }
  }

  # 4. Grants that RDS and DynamoDB create on the caller's behalf to keep resources usable
  #    asynchronously (backups, restores, background re-encryption).
  dynamic "statement" {
    for_each = local.needs_service_grants ? [1] : []

    content {
      sid    = "ServiceGrantsOnly"
      effect = "Allow"

      principals {
        type = "AWS"
        identifiers = length(var.consumer_principal_arns) > 0 ? var.consumer_principal_arns : [
          for account_id in var.consumer_account_ids : "arn:${local.partition}:iam::${account_id}:root"
        ]
      }

      actions = [
        "kms:CreateGrant",
        "kms:ListGrants",
        "kms:RevokeGrant",
      ]

      resources = ["*"]

      condition {
        test     = "Bool"
        variable = "kms:GrantIsForAWSResource"
        values   = ["true"]
      }

      condition {
        test     = "StringEquals"
        variable = "kms:CallerAccount"
        values   = var.consumer_account_ids
      }
    }
  }

  # 5. Read-only visibility for security tooling and auditors.
  dynamic "statement" {
    for_each = length(var.auditor_role_arns) > 0 ? [1] : []

    content {
      sid    = "AuditReadOnly"
      effect = "Allow"

      principals {
        type        = "AWS"
        identifiers = var.auditor_role_arns
      }

      actions = [
        "kms:DescribeKey",
        "kms:GetKeyPolicy",
        "kms:GetKeyRotationStatus",
        "kms:ListAliases",
        "kms:ListGrants",
        "kms:ListResourceTags",
      ]

      resources = ["*"]
    }
  }

  # 6. The rotation-compliance rule in each workload account resolves alias -> key ARN at
  #    evaluation time, so the alias stays the single source of truth for "current generation".
  dynamic "statement" {
    for_each = length(var.compliance_reader_arns) > 0 ? [1] : []

    content {
      sid    = "ComplianceAliasResolution"
      effect = "Allow"

      principals {
        type        = "AWS"
        identifiers = var.compliance_reader_arns
      }

      actions   = ["kms:DescribeKey"]
      resources = ["*"]
    }
  }

  # 7. Destructive operations are break-glass only. Without this, any key admin could put every
  #    ciphertext encrypted under this key beyond recovery.
  dynamic "statement" {
    for_each = length(var.break_glass_role_arns) > 0 ? [1] : []

    content {
      sid    = "BreakGlassDestructiveOperations"
      effect = "Allow"

      principals {
        type        = "AWS"
        identifiers = var.break_glass_role_arns
      }

      actions = [
        "kms:DeleteImportedKeyMaterial",
        "kms:ScheduleKeyDeletion",
      ]

      resources = ["*"]
    }
  }

  statement {
    sid    = "DenyDestructiveOperationsOutsideBreakGlass"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = [
      "kms:DeleteImportedKeyMaterial",
      "kms:ScheduleKeyDeletion",
    ]

    resources = ["*"]

    dynamic "condition" {
      for_each = length(var.break_glass_role_arns) > 0 ? [1] : []

      content {
        test     = "ArnNotEquals"
        variable = "aws:PrincipalArn"
        values   = var.break_glass_role_arns
      }
    }
  }
}

# ---------------------------------------------------------------------------------------------------
# The key itself.
#
# key_material_base64 is intentionally NOT managed by Terraform: the provider would need the raw
# 256-bit material as an input, which would land in plaintext in the state file. The key is created
# in PendingImport state and the material is imported by the ceremony described in
# docs/rotation-runbook.md, wrapped inside the on-premises HSM.
# ---------------------------------------------------------------------------------------------------
resource "aws_kms_external_key" "this" {
  description             = "BYOK ${upper(var.service)} encryption key - ${var.environment} - generation ${var.generation}"
  deletion_window_in_days = var.deletion_window_in_days
  enabled                 = var.enabled
  multi_region            = var.multi_region
  policy                  = data.aws_iam_policy_document.key.json
  valid_to                = var.key_material_valid_to

  tags = local.tags

  lifecycle {
    # 'enabled' and 'valid_to' are driven by the out-of-band import ceremony; re-importing material
    # must never be a Terraform diff.
    ignore_changes = [enabled, valid_to]
  }
}

# Immutable, per-generation alias. Gives ciphertexts and CloudTrail a stable human-readable name
# even after the service alias has moved on.
resource "aws_kms_alias" "generation" {
  name          = local.generation_alias
  target_key_id = aws_kms_external_key.this.id
}

# The alias every workload references. Moving this pointer is the rotation.
resource "aws_kms_alias" "service" {
  count = var.is_current_generation ? 1 : 0

  name          = local.service_alias
  target_key_id = aws_kms_external_key.this.id
}
