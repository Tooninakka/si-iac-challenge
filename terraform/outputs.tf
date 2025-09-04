output "api_endpoint" {
  description = "The endpoint of the API Gateway"
  value       = aws_api_gatewayv2_api.http_api.api_endpoint
  
}

output "lambda_function_name" {
  description = "The name of the Lambda function"
  value       = aws_lambda_function.app.function_name
  
}

output "s3_bucket" {
  description = "The name of the S3 bucket"
  value       = aws_s3_bucket.bucket.bucket
  
}