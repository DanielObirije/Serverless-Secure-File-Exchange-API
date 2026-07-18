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

