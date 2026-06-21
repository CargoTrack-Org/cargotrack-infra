variable "aws_region" {
  type = string
}

variable "project_name" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "alarm_email" {
  type        = string
  description = "Email address for CloudWatch alarm SNS notifications. Leave null to skip email subscription."
  default     = null
}
