variable "region" {
  type    = string
  default = "us-east-1"
}

variable "terraform_execution_role_arn" {
  description = "Role Terraform assumes to manage GitLab infrastructure."
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "ami_id" {
  description = "GitLab application server AMI (Amazon Linux 2 or Ubuntu with GitLab pre-installed)."
  type        = string
}

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS."
  type        = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "alarm_email" {
  description = "Email address for CloudWatch alarm notifications."
  type        = string
}

variable "default_tags" {
  type = map(string)
  default = {
    Project   = "gitlab"
    ManagedBy = "terraform"
  }
}
