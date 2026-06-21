terraform {

  backend "s3" {

    bucket         = "cargotrack-terraform-state"
    key            = "environments/prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "cargotrack-terraform-locks"
    encrypt        = true
  }
}
