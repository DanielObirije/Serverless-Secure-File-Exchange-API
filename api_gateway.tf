# # API GATEWAY RESOURCES

# Rest API
resource "aws_apigatewayv2_api" "file_sharing_api" {
  name          = "${local.project_name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST","OPTIONS"]
    allow_headers = ["*"]
  }

  tags = merge(local.common_tags, {
    Name = "File Sharing API"
     Description = "HTTP API for file sharing service"
  })
}


# # API GATEWAY INTEGRATIONS

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.file_sharing_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.presigned_url_api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "health" {
  api_id    = aws_apigatewayv2_api.file_sharing_api.id
  route_key = "GET /health"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "upload" {
  api_id    = aws_apigatewayv2_api.file_sharing_api.id
  route_key = "POST /upload-url"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "download" {
  api_id    = aws_apigatewayv2_api.file_sharing_api.id
  route_key = "POST /download-url"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# API GATEWAY DEPLOYMENT & STAGE
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.file_sharing_api.id
  name        = "$default"
  auto_deploy = true

 access_log_settings {
   destination_arn = aws_cloudwatch_log_group.api_gateway_logs.arn
   format = jsonencode({
      requestId               = "$context.requestId"
      ip                      = "$context.identity.sourceIp"
      caller                  = "$context.identity.caller"
      user                    = "$context.identity.user"
      requestTime             = "$context.requestTime"
      httpMethod              = "$context.httpMethod"
      resourcePath            = "$context.resourcePath"
      status                  = "$context.status"
      protocol                = "$context.protocol"
      responseLength          = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
    })
 }
 tags = merge(local.common_tags, {
  Name        = "API Gateway $default Stage"
  Description = "Default stage with automatic deployment for file sharing API"
})
}