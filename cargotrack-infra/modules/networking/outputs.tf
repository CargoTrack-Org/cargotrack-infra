output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"

  value = [
    for k, subnet in aws_subnet.subnets :
    subnet.id
    if subnet.tags["Tier"] == "public"
  ]
}

output "web_subnet_ids" {
  description = "Web subnet IDs"

  value = [
    for k, subnet in aws_subnet.subnets :
    subnet.id
    if subnet.tags["Tier"] == "web"
  ]
}

output "app_subnet_ids" {
  description = "App subnet IDs"

  value = [
    for k, subnet in aws_subnet.subnets :
    subnet.id
    if subnet.tags["Tier"] == "app"
  ]
}

output "db_subnet_ids" {
  description = "Database subnet IDs"

  value = [
    for k, subnet in aws_subnet.subnets :
    subnet.id
    if subnet.tags["Tier"] == "db"
  ]
}

output "web_route_table_id" {
  description = "Web-tier private route table ID"
  value       = aws_route_table.web.id
}

output "app_route_table_id" {
  description = "App-tier private route table ID"
  value       = aws_route_table.app.id
}

output "db_route_table_id" {
  description = "Database-tier private route table ID"
  value       = aws_route_table.db.id
}
