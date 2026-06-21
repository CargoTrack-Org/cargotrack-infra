variable "project_name" {
  type = string
}

variable "db_subnet_ids" {
  type = list(string)
}

variable "database_sg_id" {
  type = string
}