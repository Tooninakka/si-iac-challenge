variable "aws_region" {
  type    = string
  default = "eu-west-2"
}

variable "project_name" {
  type    = string
  default = "si-iac-challenge"
}

variable "lambda_runtime" {
  type    = string
  default = "python3.9"
}

variable "enable_versioning" {
  type    = bool
  default = true
}

variable "force_destroy" {
  type    = bool
  default = true
}

variable "log_retention" {
  type    = number
  default = 14
}

variable "environment" {
  type    = string
  default = "dev"
}