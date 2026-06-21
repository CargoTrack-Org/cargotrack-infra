locals {
  common_tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

resource "aws_dynamodb_table" "audit" {

  name         = "${var.project_name}-audit"
  billing_mode = "PAY_PER_REQUEST"

  hash_key  = "shipmentId"
  range_key = "timestamp"

  attribute {
    name = "shipmentId"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = merge(
    local.common_tags,
    {
      Name    = "${var.project_name}-audit"
      Purpose = "Audit trail for shipment and document events"
    }
  )
}
