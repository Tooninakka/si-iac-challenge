terraform {
  backend "s3" {
    bucket = "my-terraform-state-bucket"
    key    = "si-iac/terraform.tfstate"
    region = "eu-west-2"
    dynamodb_table = "terraform-locks"
    encrypt = true
  }
}