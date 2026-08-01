resource "terraform_data" "lambda_build" {
  triggers_replace = [
    filemd5("${path.module}/lambda/main.go"),
    filemd5("${path.module}/lambda/go.mod"),
    filemd5("${path.module}/lambda/go.sum")
  ]

  provisioner "local-exec" {
    command = <<EOF
      cd ${path.module}/lambda
      GOOS=linux GOARCH=amd64 go build -o bootstrap main.go
    EOF
  }
}

#Data source to get the Lambda zip file
data "archive_file" "lambda_zip"{
  type = "zip"
  source_dir = "${path.module}/lambda"
  output_path = "${path.module}/lambda-function.zip"
  excludes = [ 
     ".git",
    "*.go",
    "go.mod",
    "go.sum"
   ]
    depends_on = [terraform_data.lambda_build]
}

# Lambda function
resource "aws_lambda_function" "presigned_url_api" {
  filename = data.archive_file.lambda_zip.output_path
  function_name = "${local.project_name}-presigned-url-api"
  role = aws_iam_role.lambda_execution_role.arn
  handler = "bootstrap"
  runtime = "provided.al2023"
  timeout          = 10 
  memory_size      = 128
  reserved_concurrent_executions = 10

  environment {
    variables = {
       BUCKET_NAME = aws_s3_bucket.file_sharing.bucket
      AWS_REGION  = data.aws_region.current.name
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_logs,
    aws_iam_role_policy_attachment.lambda_s3_access
  ]
  
  tags = merge(local.common_tags, {
    Name = "Presigned URL API Lambda"
    Description = "Lambda for generating presigned URLs"
  })
   
}

# LAMBDA PERMISSIONS FOR API GATEWAY
resource "aws_lambda_permission" "api_gateway_health" {
   statement_id  = "AllowAPIGatewayInvoke-Health"
   action        = "lambda:InvokeFunction"
   function_name = aws_lambda_function.presigned_url_api.function_name
   principal     = "apigateway.amazonaws.com"
   source_arn = "${aws_apigatewayv2_api.file_sharing_api.execution_arn}/*/GET/health"
}


resource "aws_lambda_permission" "api_gateway_upload" {
   statement_id  = "AllowAPIGatewayInvoke-Upload"
   action        = "lambda:InvokeFunction"
   function_name = aws_lambda_function.presigned_url_api.function_name
   principal     = "apigateway.amazonaws.com"
   source_arn = "${aws_apigatewayv2_api.file_sharing_api.execution_arn}/*/POST/upload-url"
}

resource "aws_lambda_permission" "api_gateway_download" {
   statement_id  = "AllowAPIGatewayInvoke-Download"
   action        = "lambda:InvokeFunction"
   function_name = aws_lambda_function.presigned_url_api.function_name
   principal     = "apigateway.amazonaws.com"
   source_arn = "${aws_apigatewayv2_api.file_sharing_api.execution_arn}/*/POST/download-url"
}