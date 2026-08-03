# Data source for current AWS caller identity
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
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
  enable_notifications = true
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