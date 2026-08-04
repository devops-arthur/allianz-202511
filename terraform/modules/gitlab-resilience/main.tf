data "aws_region" "current" {}

# ── Security Groups ───────────────────────────────────────────────────────────

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "GitLab ALB — HTTPS inbound"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = var.tags
}

resource "aws_security_group" "app" {
  name        = "${var.name}-app"
  description = "GitLab app servers — traffic from ALB only"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = var.tags
}

resource "aws_security_group" "efs" {
  name        = "${var.name}-efs"
  description = "EFS mount targets — NFS from app servers only"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }
  tags = var.tags
}

resource "aws_security_group" "rds" {
  name        = "${var.name}-rds"
  description = "RDS — Postgres from app servers only"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }
  tags = var.tags
}

# ── EFS (shared GitLab data — replaces per-instance EBS) ─────────────────────

resource "aws_efs_file_system" "gitlab" {
  encrypted        = true
  throughput_mode  = var.efs_throughput_mode
  lifecycle_policy { transition_to_ia = "AFTER_30_DAYS" }
  tags = merge(var.tags, { Name = "${var.name}-efs" })
}

resource "aws_efs_mount_target" "gitlab" {
  for_each        = toset(var.private_subnet_ids)
  file_system_id  = aws_efs_file_system.gitlab.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_backup_policy" "gitlab" {
  file_system_id = aws_efs_file_system.gitlab.id
  backup_policy { status = "ENABLED" }
}

# ── RDS Multi-AZ PostgreSQL ───────────────────────────────────────────────────

resource "aws_db_subnet_group" "gitlab" {
  name       = "${var.name}-rds"
  subnet_ids = var.private_subnet_ids
  tags       = var.tags
}

resource "aws_db_instance" "gitlab" {
  identifier              = "${var.name}-postgres"
  engine                  = "postgres"
  engine_version          = "16"
  instance_class          = var.db_instance_class
  db_name                 = var.db_name
  username                = var.db_username
  password                = var.db_password
  db_subnet_group_name    = aws_db_subnet_group.gitlab.name
  vpc_security_group_ids  = [aws_security_group.rds.id]
  multi_az                = true
  storage_encrypted       = true
  backup_retention_period = var.db_backup_retention_days
  deletion_protection     = true
  skip_final_snapshot     = false
  final_snapshot_identifier = "${var.name}-postgres-final"
  tags                    = var.tags
}

# ── ALB ───────────────────────────────────────────────────────────────────────

resource "aws_lb" "gitlab" {
  name               = "${var.name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids
  tags               = var.tags
}

resource "aws_lb_target_group" "gitlab" {
  name     = "${var.name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path                = "/-/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
  }
  tags = var.tags
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.gitlab.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gitlab.arn
  }
}

# ── Launch Template ───────────────────────────────────────────────────────────

resource "aws_iam_instance_profile" "gitlab" {
  name = "${var.name}-instance-profile"
  role = aws_iam_role.gitlab_instance.name
}

resource "aws_iam_role" "gitlab_instance" {
  name = "${var.name}-instance-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.gitlab_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_launch_template" "gitlab" {
  name_prefix   = "${var.name}-"
  image_id      = var.ami_id
  instance_type = var.instance_type

  iam_instance_profile { arn = aws_iam_instance_profile.gitlab.arn }
  vpc_security_group_ids = [aws_security_group.app.id]

  metadata_options {
    http_tokens = "required" # IMDSv2 only
  }

  user_data = base64encode(templatefile("${path.module}/userdata.sh.tpl", {
    efs_dns = aws_efs_file_system.gitlab.dns_name
    db_host = aws_db_instance.gitlab.address
    db_name = var.db_name
    db_user = var.db_username
  }))

  tags = var.tags
}

# ── Auto Scaling Group ────────────────────────────────────────────────────────

resource "aws_autoscaling_group" "gitlab" {
  name                = "${var.name}-asg"
  min_size            = var.asg_min
  max_size            = var.asg_max
  desired_capacity    = var.asg_desired
  vpc_zone_identifier = var.private_subnet_ids
  target_group_arns   = [aws_lb_target_group.gitlab.arn]
  health_check_type   = "ELB"

  launch_template {
    id      = aws_launch_template.gitlab.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
    preferences { min_healthy_percentage = 50 }
  }

  tag {
    key                 = "Name"
    value               = "${var.name}-app"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = var.tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

resource "aws_autoscaling_policy" "scale_out" {
  name                   = "${var.name}-scale-out"
  autoscaling_group_name = aws_autoscaling_group.gitlab.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 70.0
  }
}

# ── CloudWatch Alarms ─────────────────────────────────────────────────────────

locals {
  alarms = {
    rds_cpu = {
      metric      = "CPUUtilization"
      namespace   = "AWS/RDS"
      threshold   = 80
      dimensions  = { DBInstanceIdentifier = aws_db_instance.gitlab.id }
      description = "RDS CPU > 80%"
    }
    rds_storage = {
      metric      = "FreeStorageSpace"
      namespace   = "AWS/RDS"
      threshold   = 10737418240 # 10 GB
      comparison  = "LessThanThreshold"
      dimensions  = { DBInstanceIdentifier = aws_db_instance.gitlab.id }
      description = "RDS free storage < 10 GB"
    }
    alb_5xx = {
      metric      = "HTTPCode_Target_5XX_Count"
      namespace   = "AWS/ApplicationELB"
      threshold   = 50
      dimensions  = { LoadBalancer = aws_lb.gitlab.arn_suffix }
      description = "ALB 5xx errors > 50 in 5 min"
    }
    asg_cpu = {
      metric      = "CPUUtilization"
      namespace   = "AWS/EC2"
      threshold   = 85
      dimensions  = { AutoScalingGroupName = aws_autoscaling_group.gitlab.name }
      description = "App server CPU > 85%"
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "gitlab" {
  for_each = local.alarms

  alarm_name          = "${var.name}-${each.key}"
  alarm_description   = each.value.description
  namespace           = each.value.namespace
  metric_name         = each.value.metric
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = each.value.threshold
  comparison_operator = lookup(each.value, "comparison", "GreaterThanThreshold")
  dimensions          = each.value.dimensions
  alarm_actions       = [var.alarm_sns_arn]
  ok_actions          = [var.alarm_sns_arn]
  tags                = var.tags
}

# ── EFS CloudWatch Alarm ──────────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "efs_burst_credit" {
  alarm_name          = "${var.name}-efs-burst-credit-low"
  alarm_description   = "EFS burst credit balance low — throughput may be throttled"
  namespace           = "AWS/EFS"
  metric_name         = "BurstCreditBalance"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 1073741824 # 1 GB
  comparison_operator = "LessThanThreshold"
  dimensions          = { FileSystemId = aws_efs_file_system.gitlab.id }
  alarm_actions       = [var.alarm_sns_arn]
  tags                = var.tags
}
