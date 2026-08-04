# SNS topic for all CloudWatch alarm notifications
resource "aws_sns_topic" "gitlab_alarms" {
  name = "gitlab-alarms"
  tags = var.default_tags
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.gitlab_alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

module "gitlab" {
  source = "../../modules/gitlab-resilience"

  vpc_id             = var.vpc_id
  public_subnet_ids  = var.public_subnet_ids
  private_subnet_ids = var.private_subnet_ids
  ami_id             = var.ami_id
  certificate_arn    = var.certificate_arn
  db_password        = var.db_password
  alarm_sns_arn      = aws_sns_topic.gitlab_alarms.arn
  tags               = var.default_tags
}
