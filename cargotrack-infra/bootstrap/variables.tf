variable "aws_region" {
  description = "AWS region where the state bucket and lock table are created"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name — used as a prefix for resource naming"
  type        = string
  default     = "cargotrack"
}
