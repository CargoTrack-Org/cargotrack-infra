variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "app_subnet_ids" {
  description = "App-tier private subnet IDs for interface endpoints"
  type        = list(string)
}

variable "backend_sg_id" {
  description = "Backend EC2 security group ID — allowed to reach the interface endpoints on port 443"
  type        = string
}

variable "private_route_table_ids" {
  description = "Route table IDs for all private subnets (web, app, db) — S3 gateway endpoint routes are injected here"
  type        = list(string)
}
