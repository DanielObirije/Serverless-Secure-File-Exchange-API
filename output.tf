output "api_gateway_url" {
  description = "API Gateway endpoint URL"
  value       = "${aws_apigatewayv2_stage.default.invoke_url}"
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.presigned_url_api.function_name
}

output "s3_bucket_name" {
  description = "S3 bucket name"
  value       = aws_s3_bucket.file_sharing.bucket
}

output "api_endpoints" {
  description = "API endpoints"

  value = {
    health       = "${aws_apigatewayv2_stage.default.invoke_url}/health"
    upload_url   = "${aws_apigatewayv2_stage.default.invoke_url}/upload-url"
    download_url = "${aws_apigatewayv2_stage.default.invoke_url}/download-url"
  }
}