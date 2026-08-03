#Iam role for lambda execution
resource "aws_iam_role" "lambda_execution_role" {
  name = "${local.project_name}-lambda_execution_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      } 
    ]
  })
  tags = merge(local.common_tags, {
    Name = "Lambda Execution Role"
    Description = "IAM role for Lambda function execution"
  })
}

# IAM policy for Lambda to write logs
resource "aws_iam_role_policy_attachment" "lambda_logs" { 
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}


# IAM Policy for S3 access
resource "aws_iam_policy" "lambda_s3_policy" {
  name = "${local.bucket_name}-lambda_s3_policy"
  description = "Allows Lambda to generate presigned URLs for S3"
  policy = jsonencode({
       Version = "2012-10-17"
       Statement = [
        {
          Effect = "Allow"
          Action = [
            "s3:GetObject",
            "s3:PutObject",
            "s3:DeleteObject",
            "s3:GetObjectVersion",
            "s3:PutObjectAcl",
            "s3:AbortMultipartUpload",
            "s3:ListMultipartUploadParts"
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
          Condition = {
            StringLike = {
              "s3:prefix" = [
                "uploads/*",
                "documents/*"
              ]
            }
          }
        }
       ]
  })
}

# IAM policy for Lambda to access S3
resource "aws_iam_role_policy_attachment" "lambda_s3_access" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_s3_policy.arn
}




# IAM role for CloudTrail logs
resource "aws_iam_role" "cloudtrail_logs" {
   count =  local.enable_cloudtrail_logging ? 1 : 0
   name = "${local.project_name}-cloudtrail-logs-role"
   assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement =[
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
         Service = "cloudtrail.amazonaws.com",
        }
      }
    ]
  })

  tags = local.common_tags
}

# IAM policy for CloudTrail to write to CloudWatch Logs
resource "aws_iam_role_policy" "cloudtrail_logs" {
  count =  local.enable_cloudtrail_logging ? 1 : 0
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

# resource "aws_s3_bucket_policy" "file_sharing" {
#   bucket = aws_s3_bucket.file_sharing.id

#   policy = jsonencode({
#     Version = "2012-10-17"

#     Statement = [
#       {
#         Sid    = "DenyHTTP"
#         Effect = "Deny"

#         Principal = "*"

#         Action = "s3:*"

#         Resource = [
#           aws_s3_bucket.file_sharing.arn,
#           "${aws_s3_bucket.file_sharing.arn}/*"
#         ]

#         Condition = {
#           Bool = {
#             "aws:SecureTransport" = "false"
#           }
#         }
#       }
#     ]
#   })
# }

resource "aws_s3_bucket_policy" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [

      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"

        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }

        Action = "s3:GetBucketAcl"

        Resource = aws_s3_bucket.access_logs.arn
      },

      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"

        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }

        Action = "s3:PutObject"

        Resource = "${aws_s3_bucket.access_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"

        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },

      {
        Sid = "DenyHTTP"
        Effect = "Deny"

        Principal = "*"

        Action = "s3:*"

        Resource = [
          aws_s3_bucket.access_logs.arn,
          "${aws_s3_bucket.access_logs.arn}/*"
        ]

        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}