variable "project_name" {
  description = "Project name prefix for GuardDuty resource names"
  type        = string
}

variable "alarm_email" {
  description = "Email for GuardDuty HIGH/CRITICAL finding alerts. Set to null or empty string to disable SNS notifications."
  type        = string
  default     = null
}

variable "kms_key_arn" {
  description = "KMS key ARN for encrypting the GuardDuty alerts SNS topic"
  type        = string
}
