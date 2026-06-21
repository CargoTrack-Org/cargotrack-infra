variable "project_name" {
  description = "Project name"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the customer managed KMS key used for S3 SSE-KMS encryption"
  type        = string
}
