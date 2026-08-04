locals {
  account_labels     = keys(var.target_accounts)
  # Compute bootstrap role ARNs from account IDs — no manual input needed.
  bootstrap_role_arns = [
    for label in local.account_labels :
    "arn:aws:iam::${var.target_accounts[label]}:role/${var.bootstrap_role_name}"
  ]
}

# ── Step 1: Bootstrap role in each target account ────────────────────────────
# Deployed via the default (management) provider using cross-account assume-role.
# Grants only the permission to assume the terraform-execution role in the same account.

data "aws_iam_openid_connect_provider" "ci" {
  for_each = var.target_accounts
  arn      = var.oidc_provider_arn_by_account[each.key]
}

data "aws_iam_policy_document" "bootstrap_trust" {
  for_each = var.target_accounts

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.ci[each.key].arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${data.aws_iam_openid_connect_provider.ci[each.key].url}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "${data.aws_iam_openid_connect_provider.ci[each.key].url}:sub"
      values   = var.oidc_subjects
    }
  }
}

data "aws_iam_policy_document" "bootstrap_permissions" {
  for_each = var.target_accounts

  statement {
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = ["arn:aws:iam::${each.value}:role/${var.terraform_role_name}"]
  }
}

resource "aws_iam_role" "bootstrap" {
  for_each           = var.target_accounts
  name               = var.bootstrap_role_name
  assume_role_policy = data.aws_iam_policy_document.bootstrap_trust[each.key].json
  tags               = var.default_tags
}

resource "aws_iam_role_policy" "bootstrap_permissions" {
  for_each = var.target_accounts
  name     = "assume-terraform-execution"
  role     = aws_iam_role.bootstrap[each.key].name
  policy   = data.aws_iam_policy_document.bootstrap_permissions[each.key].json
}

# ── Step 2: Terraform execution role in each target account ──────────────────
# Deployed via aliased providers that assume the bootstrap roles created above.

module "terraform_role_account_0" {
  source    = "../../modules/iam-terraform-role"
  providers = { aws = aws.account_0 }

  role_name         = var.terraform_role_name
  oidc_provider_arn = var.oidc_provider_arn_by_account[local.account_labels[0]]
  oidc_subjects     = var.oidc_subjects
  tags              = var.default_tags

  depends_on = [aws_iam_role.bootstrap, aws_iam_role_policy.bootstrap_permissions]
}

module "terraform_role_account_1" {
  source    = "../../modules/iam-terraform-role"
  providers = { aws = aws.account_1 }

  role_name         = var.terraform_role_name
  oidc_provider_arn = var.oidc_provider_arn_by_account[local.account_labels[1]]
  oidc_subjects     = var.oidc_subjects
  tags              = var.default_tags

  depends_on = [aws_iam_role.bootstrap, aws_iam_role_policy.bootstrap_permissions]
}
