variable "name" {
  description = "Name prefix for all resources."
  type        = string
  default     = "gitlab"
}

variable "vpc_id" {
  description = "VPC to deploy GitLab into."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnets for the ALB."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnets for GitLab app servers and RDS."
  type        = list(string)
}

variable "ami_id" {
  description = "AMI ID for GitLab application servers."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for GitLab app servers."
  type        = string
  default     = "m6i.xlarge"
}

variable "asg_min" {
  type    = number
  default = 2
}

variable "asg_max" {
  type    = number
  default = 6
}

variable "asg_desired" {
  type    = number
  default = 2
}

variable "efs_throughput_mode" {
  description = "EFS throughput mode: bursting or provisioned."
  type        = string
  default     = "bursting"
}

variable "db_instance_class" {
  type    = string
  default = "db.m6g.large"
}

variable "db_name" {
  type    = string
  default = "gitlabhq_production"
}

variable "db_username" {
  type    = string
  default = "gitlab"
}

variable "db_password" {
  description = "RDS master password — supply via tfvars or Secrets Manager reference."
  type        = string
  sensitive   = true
}

variable "db_backup_retention_days" {
  type    = number
  default = 7
}

variable "alarm_sns_arn" {
  description = "SNS topic ARN for CloudWatch alarm notifications."
  type        = string
}

variable "certificate_arn" {
  description = "ACM certificate ARN for the ALB HTTPS listener."
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
