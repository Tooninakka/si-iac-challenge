terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.2" }
    random = { source = "hashicorp/random", version = "~> 3.5" }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "random_string" "suffix" {
  length = 6
  override_special = false
  upper = false
  numeric = true
}

# S3 bucket (private, server-side encrypted, versioned)
resource "aws_s3_bucket" "bucket" {
  bucket = "${var.project_name}-${random_string.suffix.result}"
  acl    = "private"
  force_destroy = var.force_destroy

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  versioning { enabled = var.enable_versioning }

  tags = {
    Name = var.project_name
    Environment = var.environment
  }
}

resource "aws_s3_bucket_public_access_block" "block" {
  bucket = aws_s3_bucket.bucket.id
  block_public_acls = true
  block_public_policy = true
  ignore_public_acls = true
  restrict_public_buckets = true
}

# IAM Role for Lambda (least-privilege)
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-exec"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
  tags = { Name = var.project_name }
}

resource "aws_iam_policy" "lambda_policy" {
  name = "${var.project_name}-lambda-policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents"],
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow",
        Action = ["s3:ListBucket"],
        Resource = aws_s3_bucket.bucket.arn
      },
      {
        Effect = "Allow",
        Action = ["s3:GetObject"],
        Resource = "${aws_s3_bucket.bucket.arn}/*"
      },
      {
        Effect = "Allow",
        Action = ["xray:PutTraceSegments","xray:PutTelemetryRecords"],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Build the Lambda zip from the ../lambda directory (archive provider)
data "archive_file" "lambda_zip" {
  type = "zip"
  source_dir = "${path.module}/../lambda"
  output_path = "${path.module}/lambda.zip"
}

# Lambda function
resource "aws_lambda_function" "app" {
  function_name = "${var.project_name}-list-s3"
  filename = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  handler = "lambda_function.lambda_handler"
  runtime = var.lambda_runtime
  role = aws_iam_role.lambda_role.arn
  timeout = 10
  memory_size = 128
  environment { variables = { BUCKET_NAME = aws_s3_bucket.bucket.bucket } }
  tracing_config { mode = "Active" }
  tags = { Name = var.project_name }
  depends_on = [aws_iam_role_policy_attachment.lambda_policy_attach]
}

# Ensure CloudWatch log retention exists (Lambda creates the group automatically, but we set retention)
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name = "/aws/lambda/${aws_lambda_function.app.function_name}"
  retention_in_days = var.log_retention
  tags = { Name = var.project_name }
}

# HTTP API (API Gateway v2) and integration
resource "aws_apigatewayv2_api" "http_api" {
  name = "${var.project_name}-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id = aws_apigatewayv2_api.http_api.id
  integration_type = "AWS_PROXY"
  integration_uri = aws_lambda_function.app.invoke_arn
  integration_method = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "default_route" {
  api_id = aws_apigatewayv2_api.http_api.id
  route_key = "GET /"
  target = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id = aws_apigatewayv2_api.http_api.id
  name = "$default"
  auto_deploy = true
}

# Permission for API Gateway to invoke the Lambda
resource "aws_lambda_permission" "apigw" {
  statement_id = "AllowAPIGatewayInvoke"
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.app.function_name
  principal = "apigateway.amazonaws.com"
  source_arn = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

# CloudWatch dashboard (simple) and SNS + Alarm for errors
locals {
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric",
        x = 0,
        y = 0,
        width = 24,
        height = 6,
        properties = {
          metrics = [
            ["AWS/Lambda","Invocations","FunctionName", aws_lambda_function.app.function_name],
            ["AWS/Lambda","Errors","FunctionName", aws_lambda_function.app.function_name]
          ],
          period = 300,
          title = "Lambda: Invocations & Errors"
        }
      }
    ]
  })
}

resource "aws_cloudwatch_dashboard" "dashboard" {
  dashboard_name = "${var.project_name}-dashboard"
  dashboard_body = local.dashboard_body
}

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name = "${var.project_name}-lambda-errors"
  namespace = "AWS/Lambda"
  metric_name = "Errors"
  dimensions = { FunctionName = aws_lambda_function.app.function_name }
  statistic = "Sum"
  period = 300
  evaluation_periods = 1
  threshold = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  alarm_actions = [aws_sns_topic.alerts.arn]
}

output "api_endpoint" {
  value = aws_apigatewayv2_api.http_api.api_endpoint
}

output "lambda_function_name" {
  value = aws_lambda_function.app.function_name
}

output "s3_bucket" {
  value = aws_s3_bucket.bucket.bucket
}