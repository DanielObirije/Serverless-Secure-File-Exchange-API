# Lambda CloudWatch Log Group
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name = "/aws/lambda/${aws_lambda_function.presigned_url_api.function_name}"
  retention_in_days = 7
  tags = merge(local.common_tags, {
    Name = "Lambda Log Group"
    Description = "CloudWatch logs for presigned URL Lambda"
  })
}

resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name              = "/aws/api-gateway/${aws_apigatewayv2_api.file_sharing_api.name}"
  retention_in_days = 7
  
  tags = merge(local.common_tags, {
    Name = "API Gateway Logs"
    Description = "Access logs for API Gateway"
  })
}

# CloudWatch Log Group for monitoring S3 access (if CloudTrail is enabled)
resource "aws_cloudwatch_log_group" "s3_access_logs" {
  count =  local.enable_cloudtrail_logging ? [1] : []
  name = "/aws/cloudtrail/${aws_s3_bucket.access_logs.bucket}"
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
  metric_name         = "AllRequests"
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