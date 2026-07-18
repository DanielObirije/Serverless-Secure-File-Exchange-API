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

# S3 bucket for access logs (if access logging is enabled)
resource "aws_s3_bucket" "access_logs" {
  bucket = "${local.access_log_bucket_name}-access-logs"
  tags = merge(local.common_tags,{
      Name = "Access log bucket"
      Description = "Stores access for the main sharing bucket"
  })
}

# Block public access for access logs bucket
resource "aws_s3_bucket_public_access_block" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  block_public_acls = true
  ignore_public_acls = true
  restrict_public_buckets = true
  block_public_policy = true 
}

# Server-side encryption for access logs bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  bucket = aws_s3_bucket_public_access_block.access_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Main S3 bucket for file sharing
resource "aws_s3_bucket" "file_sharing" {
  bucket = local.access_log_bucket_name
  tags = merge(local.common_tags,{
    Name = "File sharing bucket"
    Description = "Main bucket for secure file sharing using presigned URLs"
  })
}

# Block all public access to the file sharing bucket
# This is critical for security - files should only be accessible via presigned URLs
resource "aws_s3_bucket_public_access_block" "file_sharing" {
  bucket = aws_s3_bucket.file_sharing.id
  block_public_acls = true
  ignore_public_acls = true
  restrict_public_buckets = true
  block_public_policy = true 
}

# Enable versioning for better file management and recovery
resource "aws_s3_bucket_versioning" "file_sharing" {
  bucket = aws_s3_bucket.file_sharing.id
  versioning_configuration {
    status = "Enabled"
  }
}


# Server-side encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "file_sharing" {
  bucket = aws_s3_bucket.file_sharing.id
   rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Access logging configuration (if enabled)
resource "aws_s3_bucket_logging" "file_sharing" {
  bucket = aws_s3_bucket.file_sharing.id
  target_bucket = aws_s3_bucket.file_sharing.id
  target_prefix = "access-logs/"
}

# CORS configuration to enable web browser access to presigned URLs
resource "aws_s3_bucket_cors_configuration" "file_sharing" {
  bucket =  aws_s3_bucket_logging.file_sharing.id
  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE", "HEAD"]
    allowed_origins = ["*"]
    expose_headers = ["ETag"]
    max_age_seconds = 3000
  }
}

# Lifecycle configuration for automatic file management
resource "aws_s3_bucket_lifecycle_configuration" "file_sharing" {
  bucket = aws_s3_bucket.file_sharing.id
  dynamic "rule" { 
    for_each = local.enable_documents_transition ? [1]: []

    content {
      id = "document-lifecycle"
      status = "Enabled"

      filter {
        prefix = "documents/"
      }

      transition {
        days = 30
        storage_class = "STANDARD_IA"
      }

      transition {
        days = 90
        storage_class = "GLACIER"
      }

     noncurrent_version_transition {
        noncurrent_days = 30
         storage_class   = "STANDARD_IA"
      }

      noncurrent_version_transition {
        noncurrent_days = 60
         storage_class   = "GLACIER"
      }

    }
  }
  dynamic "rule" {
    for_each = local.enable_uploads_cleanup ? [1] : []
    content {
      id = "upload-cleanup"
      status = "Enabled"

      filter {
        prefix = "uploads/"
      }
      
      expiration {
        days = 7
      }

      noncurrent_version_expiration {
         noncurrent_days = 7
      }
      
      abort_incomplete_multipart_upload {
        days_after_initiation = 1
      }
    }
  }
}

# IAM role for presigned URL generation (for applications/services)
resource "aws_iam_role" "presigned_url_generator" {
  name = "${local.bucket_name}presigned-url-generator"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement =[
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = [
          "lambda.amazonaws.com",
          "ec2.amazonaws.com"
        ]
      }
    ]
    AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
  })

  tags = merge(local.common_tags,{
    Name = "Presigned URL Generator Role"
    Description = "IAM role for generating presigned URLs"
  })
}

# IAM policy for presigned URL generation

resource "aws_iam_role_policy" "presigned_url_generator" {
  name = "${local.bucket_name}presigned-url-policy"
  role = aws_iam_role.presigned_url_generator.id

  policy = jsondecode({
       Version = "2012-10-17"
       Statement = [
        {
          Effect = "Allow"
          Action = [
            "s3:GetObject",
            "s3:PutObject",
            "s3:DeleteObject",
            "s3:GetObjectVersion",
            "s3:PutObjectAcl"
          ]
          Resource = [
            "${aws_s3_bucket.file_sharing.arn}/*"
          ]
        },
        {
          Effect = "Allow"
          Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:GetBucketVersioning"
          ]
          Resource = "${aws_s3_bucket.file_sharing.arn}"
        }
       ]
  })
}

# CloudWatch Log Group for monitoring S3 access (if CloudTrail is enabled)

resource "aws_cloudwatch_log_group" "s3_access_logs" {
  count =  local.enable_cloudtrail_logging ? [1] : []
  name = "/aws/cloudtrail/${local.project_name}-s3-access"
  retention_in_days = 30
  
  tags = merge(local.common_tags,{
    Name = "S3 Access Logs"
    Description = "CloudWatch logs for S3 API access"
  })
}

resource "aws_cloudtrail" "s3_access" {
   count =  local.enable_cloudtrail_logging ? [1] : []
   name = "${local.project_name}-s3-cloudtrail"
   s3_bucket_name = aws_s3_bucket.file_sharing.bucket
   include_global_service_events = false
   is_multi_region_trail = false
   enable_logging = true

   cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.s3_access_logs[0].arn}:*"
   cloud_watch_logs_role_arn = aws_iam_role.cloudtrail_logs[0].arn

   event_selector {
     read_write_type = "All"
     include_management_events = false

     data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.file_sharing.arn}/*"]
     }

     data_resource {
      type   = "AWS::S3::Bucket"
      values = ["${aws_s3_bucket.file_sharing.arn}"]
     }

   }
   tags = merge(local.common_tags,{
    Name        = "S3 CloudTrail"
    Description = "CloudTrail for S3 API access logging"
   })
   
}

# IAM role for CloudTrail logs

resource "aws_iam_role" "cloudtrail_logs" {
   count =  local.enable_cloudtrail_logging ? [1] : []
   name = "${local.project_name}-cloudtrail-logs-role"
   assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement =[
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = [
          "cloudtrail.amazonaws.com",
        ]
      }
    ]
  })

  tags = local.common_tags
}

# IAM policy for CloudTrail to write to CloudWatch Logs


resource "aws_iam_role_policy" "cloudtrail_logs" {
  count =  local.enable_cloudtrail_logging ? [1] : []
   name = "${local.project_name}-cloudtrail-logs-policy"
   role = aws_iam_role.cloudtrail_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.s3_access_logs[0].arn}:*"
      }
    ]
  })
}

# SNS topic for notifications (if email is provided)
resource "aws_sns_topic" "file_sharing_alerts" {
   count =  local.notification_email ? [1] : []
   name = "${local.project_name}-file-sharing-alerts"
   tags = merge(local.common_tags, {
    Name        = "File Sharing Alerts"
    Description = "SNS topic for file sharing system alerts"
  })
}

# SNS subscription for email notifications
resource "aws_sns_topic_subscription" "file_sharing_alerts" {
  count =  local.notification_email ? [1] : []
  topic_arn =  aws_sns_topic.file_sharing_alerts[0].arn
  protocol = "email"
  endpoint = local.notification_email
}

# CloudWatch metric alarm for unusual S3 access patterns

resource "aws_cloudwatch_metric_alarm" "high_s3_requests" {
   count =  local.notification_email ? [1] : []
   alarm_name =  "${local.project_name}-high-s3-requests"
   comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "NumberOfObjects"
  namespace           = "AWS/S3"
  period              = "300"
  statistic           = "Average"
  threshold           = "1000"
  alarm_description   = "This metric monitors S3 rmequest volume"
  alarm_actions      = [aws_sns_topic.file_sharing_alerts[0].arn]

  dimensions = {
    BucketName = aws_s3_bucket.file_sharing.bucket
  }
  tags = merge(local.common_tags, {
    Name        = "High S3 Requests Alarm"
    Description = "Monitors for unusual S3 access patterns"
  })
}