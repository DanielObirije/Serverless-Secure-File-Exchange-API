# Data source for current AWS caller identity
data "aws_caller_identity" "current" {}

resource "random_string" "bucket_surffix" {
  length = 6
  special = false
  upper = false
}

locals {
  bucket_name = "file-sharing-demo${random_string.bucket_surffix.id}"
  access_log_bucket_name = "file-sharing-demo-access-log"
  enable_documents_transition = true
  enable_uploads_cleanup = true
  enable_cloudtrail_logging = true
  notification_email = "johndoe@gmail.com"
  project_name = "file-sharing-demo"
  common_tags = merge(
    {
        Project = "file-sharing-demo"
        Environment = "dev"
        ManagedBy = "terraform"
        Recipe = "s3-presigned-urls"
    }
  )
}


# #Data source to get the Lambda zip file
# data "archive_file" "lambda_zip"{
#   type = "zip"
#   source_dir = "${path.module}/lambda"
#   output_path = "${path.module}/lambda-function.zip"
#   excludes = [ 
#      ".git",
#     "*.go",
#     "go.mod",
#     "go.sum",
#     "Makefile",
#     "README.md"
#    ]
#    # check this out later the excludes and paths in golang
# }

# #Iam role for lambda execution
# resource "aws_iam_role" "lambda_execution_role" {
#   name = "${local.project_name}-lambda_execution_role"
#   assume_role_policy = jsondecode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Action = "sts:AssumeRole"
#         Effect = "Allow"
#         Principal = {
#           Service = "lambda.amazonaws.com"
#         }
#       }
#     ]
#   })
#   tags = merge(local.common_tags, {
#     Name = "Lambda Execution Role"
#     Description = "IAM role for Lambda function execution"
#   })
# }

# # IAM policy for Lambda to write logs
# resource "aws_iam_role_policy_attachment" "lambda_logs" {
#   role       = aws_iam_role.lambda_execution_role.name
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
# }

# # IAM Policy for S3 access
# resource "aws_iam_policy" "lambda_s3_policy" {
#   name = "${local.bucket_name}-lambda_s3_policy"
#   description = "Allows Lambda to generate presigned URLs for S3"
#   policy = jsondecode({
#        Version = "2012-10-17"
#        Statement = [
#         {
#           Effect = "Allow"
#           Action = [
#             "s3:GetObject",
#             "s3:PutObject",
#             "s3:DeleteObject",
#             "s3:GetObjectVersion",
#             "s3:PutObjectAcl"
#           ]
#           Resource = [
#             "${aws_s3_bucket.file_sharing.arn}/*"
#           ]
#         },
#         {
#           Effect = "Allow"
#           Action = [
#           "s3:ListBucket",
#           "s3:GetBucketLocation",
#           "s3:GetBucketVersioning"
#           ]
#           Resource = "${aws_s3_bucket.file_sharing.arn}"
#         }
#        ]
#   })
# }


# # IAM policy for Lambda to access S3
# resource "aws_iam_role_policy_attachment" "lambda_s3_access" {
#   role       = aws_iam_role.lambda_execution_role.name
#   policy_arn = aws_iam_policy.lambda_s3_policy.arn
# }

# # Lambda function
# resource "aws_lambda_function" "presigned_url_api" {
#   filename = data.archive_file.lambda_zip.output_path
#   function_name = "${local.project_name}-presigned-url-api"
#   role = aws_iam_role.lambda_execution_role.arn
#   handler = "bootstrap"  #investigate this For Go on provided.al2
#   runtime = "provided.al2"
#   timeout          = 10 #investigate this number
#   memory_size      = 128 #investigate this number

#   environment {
#     variables = {
#        BUCKET_NAME = aws_s3_bucket.file_sharing.bucket
#       AWS_REGION  = data.aws_region.current.name
#     }
#   }

#   depends_on = [
#     aws_iam_role_policy_attachment.lambda_logs, #investigate why this depnds value
#     aws_iam_role_policy_attachment.lambda_s3_access #investigate why this depnds value
#   ]
  
#   tags = merge(local.common_tags, {
#     Name = "Presigned URL API Lambda"
#     Description = "Lambda for generating presigned URLs"
#   })
   
# }

# # Lambda CloudWatch Log Group
# resource "aws_cloudwatch_log_group" "lambda_logs" {
#   name = "/aws/lambda/${aws_lambda_function.presigned_url_api.function_name}"
#   retention_in_days = 7
#   tags = merge(local.common_tags, {
#     Name = "Lambda Log Group"
#     Description = "CloudWatch logs for presigned URL Lambda"
#   })
# }


# # # API GATEWAY RESOURCES

# # Rest API
# resource "aws_apigatewayv2_api" "file_sharing_api" {
#   name          = "${local.project_name}-api"
#   protocol_type = "HTTP"

#   cors_configuration {
#     allow_origins = ["*"]
#     allow_methods = ["GET", "POST","OPTIONS"]
#     allow_headers = ["*"]
#   }

#   tags = merge(local.common_tags, {
#     Name = "File Sharing API"
#      Description = "HTTP API for file sharing service"
#   })
# }


# # # API GATEWAY INTEGRATIONS

# resource "aws_apigatewayv2_integration" "lambda" {
#   api_id                 = aws_apigatewayv2_api.file_sharing_api.id
#   integration_type       = "AWS_PROXY"
#   integration_uri        = aws_lambda_function.presigned_url_api.invoke_arn
#   payload_format_version = "2.0"
# }

# resource "aws_apigatewayv2_route" "health" {
#   api_id    = aws_apigatewayv2_api.file_sharing_api.id
#   route_key = "GET /health"
#   target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
# }

# resource "aws_apigatewayv2_route" "upload" {
#   api_id    = aws_apigatewayv2_api.file_sharing_api.id
#   route_key = "POST /upload-url"
#   target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
# }

# resource "aws_apigatewayv2_route" "download" {
#   api_id    = aws_apigatewayv2_api.file_sharing_api.id
#   route_key = "POST /download-url"
#   target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
# }



# # API GATEWAY DEPLOYMENT & STAGE
# resource "aws_apigatewayv2_stage" "default" {
#   api_id      = aws_apigatewayv2_api.file_sharing_api.id
#   name        = "$default"
#   auto_deploy = true

#  access_log_settings {
#    destination_arn = aws_cloudwatch_log_group.api_gateway_logs.arn
#    format = jsonencode({
#       requestId               = "$context.requestId"
#       ip                      = "$context.identity.sourceIp"
#       caller                  = "$context.identity.caller"
#       user                    = "$context.identity.user"
#       requestTime             = "$context.requestTime"
#       httpMethod              = "$context.httpMethod"
#       resourcePath            = "$context.resourcePath"
#       status                  = "$context.status"
#       protocol                = "$context.protocol"
#       responseLength          = "$context.responseLength"
#       integrationErrorMessage = "$context.integrationErrorMessage"
#     })
#  }
#  tags = merge(local.common_tags, {
#   Name        = "API Gateway $default Stage"
#   Description = "Default stage with automatic deployment for file sharing API"
# })
# }


# resource "aws_cloudwatch_log_group" "api_gateway_logs" {
#   name              = "/aws/api-gateway/${aws_api_gateway_rest_api.file_sharing_api.name}"
#   retention_in_days = 7
  
#   tags = merge(local.common_tags, {
#     Name = "API Gateway Logs"
#     Description = "Access logs for API Gateway"
#   })
# }

# # LAMBDA PERMISSIONS FOR API GATEWAY
# resource "aws_lambda_permission" "api_gateway_health" {
#    statement_id  = "AllowAPIGatewayInvoke-Health"
#    action        = "lambda:InvokeFunction"
#    function_name = aws_lambda_function.presigned_url_api.function_name
#    principal     = "apigateway.amazonaws.com"
#    source_arn = "${aws_apigatewayv2_api.file_sharing_api.execution_arn}/*/GET/health"
# }


# resource "aws_lambda_permission" "api_gateway_upload" {
#    statement_id  = "AllowAPIGatewayInvoke-Upload"
#    action        = "lambda:InvokeFunction"
#    function_name = aws_lambda_function.presigned_url_api.function_name
#    principal     = "apigateway.amazonaws.com"
#    source_arn = "${aws_apigatewayv2_api.file_sharing_api.execution_arn}/*/POST/upload-url"
# }

# resource "aws_lambda_permission" "api_gateway_download" {
#    statement_id  = "AllowAPIGatewayInvoke-Download"
#    action        = "lambda:InvokeFunction"
#    function_name = aws_lambda_function.presigned_url_api.function_name
#    principal     = "apigateway.amazonaws.com"
#    source_arn = "${aws_apigatewayv2_api.file_sharing_api.execution_arn}/*/POST/download-url"
# }


# # S3 bucket for access logs (if access logging is enabled)
# resource "aws_s3_bucket" "access_logs" {
#   bucket = "${local.access_log_bucket_name}-access-logs"
#   tags = merge(local.common_tags,{
#       Name = "Access log bucket"
#       Description = "Stores access for the main sharing bucket"
#   })
# }


# # Block public access for access logs bucket
# resource "aws_s3_bucket_public_access_block" "access_logs" {
#   bucket = aws_s3_bucket.access_logs.id
#   block_public_acls = true
#   ignore_public_acls = true
#   restrict_public_buckets = true
#   block_public_policy = true 
# }

# # Server-side encryption for access logs bucket
# resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
#   bucket = aws_s3_bucket_public_access_block.access_logs.id
#   rule {
#     apply_server_side_encryption_by_default {
#       sse_algorithm = "AES256"
#     }
#   }
# }

# # Main S3 bucket for file sharing
# resource "aws_s3_bucket" "file_sharing" {
#   bucket = local.access_log_bucket_name
#   tags = merge(local.common_tags,{
#     Name = "File sharing bucket"
#     Description = "Main bucket for secure file sharing using presigned URLs"
#   })
# }

# # Block all public access to the file sharing bucket
# # This is critical for security - files should only be accessible via presigned URLs
# resource "aws_s3_bucket_public_access_block" "file_sharing" {
#   bucket = aws_s3_bucket.file_sharing.id
#   block_public_acls = true
#   ignore_public_acls = true
#   restrict_public_buckets = true
#   block_public_policy = true 
# }

# # Enable versioning for better file management and recovery
# resource "aws_s3_bucket_versioning" "file_sharing" {
#   bucket = aws_s3_bucket.file_sharing.id
#   versioning_configuration {
#     status = "Enabled"
#   }
# }


# # Server-side encryption configuration
# resource "aws_s3_bucket_server_side_encryption_configuration" "file_sharing" {
#   bucket = aws_s3_bucket.file_sharing.id
#    rule {
#     apply_server_side_encryption_by_default {
#       sse_algorithm = "AES256"
#     }
#   }
# }

# # Access logging configuration (if enabled)
# resource "aws_s3_bucket_logging" "file_sharing" {
#   bucket = aws_s3_bucket.file_sharing.id
#   target_bucket = aws_s3_bucket.file_sharing.id
#   target_prefix = "access-logs/"
# }

# # CORS configuration to enable web browser access to presigned URLs
# resource "aws_s3_bucket_cors_configuration" "file_sharing" {
#   bucket =  aws_s3_bucket_logging.file_sharing.id
#   cors_rule {
#     allowed_headers = ["*"]
#     allowed_methods = ["GET", "PUT", "POST", "DELETE", "HEAD"]
#     allowed_origins = ["*"]
#     expose_headers = ["ETag"]
#     max_age_seconds = 3000
#   }
# }

# # Lifecycle configuration for automatic file management
# resource "aws_s3_bucket_lifecycle_configuration" "file_sharing" {
#   bucket = aws_s3_bucket.file_sharing.id
#   dynamic "rule" { 
#     for_each = local.enable_documents_transition ? [1]: []

#     content {
#       id = "document-lifecycle"
#       status = "Enabled"

#       filter {
#         prefix = "documents/"
#       }

#       transition {
#         days = 30
#         storage_class = "STANDARD_IA"
#       }

#       transition {
#         days = 90
#         storage_class = "GLACIER"
#       }

#      noncurrent_version_transition {
#         noncurrent_days = 30
#          storage_class   = "STANDARD_IA"
#       }

#       noncurrent_version_transition {
#         noncurrent_days = 60
#          storage_class   = "GLACIER"
#       }

#     }
#   }
#   dynamic "rule" {
#     for_each = local.enable_uploads_cleanup ? [1] : []
#     content {
#       id = "upload-cleanup"
#       status = "Enabled"

#       filter {
#         prefix = "uploads/"
#       }
      
#       expiration {
#         days = 7
#       }

#       noncurrent_version_expiration {
#          noncurrent_days = 7
#       }
      
#       abort_incomplete_multipart_upload {
#         days_after_initiation = 1
#       }
#     }
#   }
# }


# # CloudWatch Log Group for monitoring S3 access (if CloudTrail is enabled)

# resource "aws_cloudwatch_log_group" "s3_access_logs" {
#   count =  local.enable_cloudtrail_logging ? [1] : []
#   name = "/aws/cloudtrail/${local.project_name}-s3-access"
#   retention_in_days = 30
  
#   tags = merge(local.common_tags,{
#     Name = "S3 Access Logs"
#     Description = "CloudWatch logs for S3 API access"
#   })
# }

# resource "aws_cloudtrail" "s3_access" {
#    count =  local.enable_cloudtrail_logging ? [1] : []
#    name = "${local.project_name}-s3-cloudtrail"
#    s3_bucket_name = aws_s3_bucket.file_sharing.bucket
#    include_global_service_events = false
#    is_multi_region_trail = false
#    enable_logging = true

#    cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.s3_access_logs[0].arn}:*"
#    cloud_watch_logs_role_arn = aws_iam_role.cloudtrail_logs[0].arn

#    event_selector {
#      read_write_type = "All"
#      include_management_events = false

#      data_resource {
#       type   = "AWS::S3::Object"
#       values = ["${aws_s3_bucket.file_sharing.arn}/*"]
#      }

#      data_resource {
#       type   = "AWS::S3::Bucket"
#       values = ["${aws_s3_bucket.file_sharing.arn}"]
#      }

#    }
#    tags = merge(local.common_tags,{
#     Name        = "S3 CloudTrail"
#     Description = "CloudTrail for S3 API access logging"
#    })
   
# }

#keep off

# # IAM role for CloudTrail logs

# resource "aws_iam_role" "cloudtrail_logs" {
#    count =  local.enable_cloudtrail_logging ? [1] : []
#    name = "${local.project_name}-cloudtrail-logs-role"
#    assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement =[
#       {
#         Action = "sts:AssumeRole"
#         Effect = "Allow"
#         Principal = [
#           "cloudtrail.amazonaws.com",
#         ]
#       }
#     ]
#   })

#   tags = local.common_tags
# }

# # IAM policy for CloudTrail to write to CloudWatch Logs
# resource "aws_iam_role_policy" "cloudtrail_logs" {
#   count =  local.enable_cloudtrail_logging ? [1] : []
#    name = "${local.project_name}-cloudtrail-logs-policy"
#    role = aws_iam_role.cloudtrail_logs[0].id

#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Action = [
#           "logs:CreateLogStream",
#           "logs:PutLogEvents"
#         ]
#         Resource = "${aws_cloudwatch_log_group.s3_access_logs[0].arn}:*"
#       }
#     ]
#   })
# }

#keep off

# # SNS topic for notifications (if email is provided)
# resource "aws_sns_topic" "file_sharing_alerts" {
#    count =  local.notification_email ? [1] : []
#    name = "${local.project_name}-file-sharing-alerts"
#    tags = merge(local.common_tags, {
#     Name        = "File Sharing Alerts"
#     Description = "SNS topic for file sharing system alerts"
#   })
# }

# # SNS subscription for email notifications
# resource "aws_sns_topic_subscription" "file_sharing_alerts" {
#   count =  local.notification_email ? [1] : []
#   topic_arn =  aws_sns_topic.file_sharing_alerts[0].arn
#   protocol = "email"
#   endpoint = local.notification_email
# }

# # CloudWatch metric alarm for unusual S3 access patterns
# resource "aws_cloudwatch_metric_alarm" "high_s3_requests" {
#   count =  local.notification_email ? [1] : []
#   alarm_name =  "${local.project_name}-high-s3-requests"
#   comparison_operator = "GreaterThanThreshold"
#   evaluation_periods  = "2"
#   metric_name         = "AllRequests"
#   namespace           = "AWS/S3"
#   period              = "300"
#   statistic           = "Average"
#   threshold           = "1000"
#   alarm_description   = "This metric monitors S3 rmequest volume"
#   alarm_actions      = [aws_sns_topic.file_sharing_alerts[0].arn]

#   dimensions = {
#     BucketName = aws_s3_bucket.file_sharing.bucket
#   }
#   tags = merge(local.common_tags, {
#     Name        = "High S3 Requests Alarm"
#     Description = "Monitors for unusual S3 access patterns"
#   })
# }