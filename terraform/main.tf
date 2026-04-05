terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# KMS key for S3 encryption
resource "aws_kms_key" "s3_key" {
  description             = "KMS key for S3 bucket encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# S3 logging bucket
resource "aws_s3_bucket" "log_bucket" {
  # checkov:skip=CKV_AWS_18: This IS the log bucket, logging to itself is circular
  # checkov:skip=CKV2_AWS_61: Log bucket lifecycle managed separately
  # checkov:skip=CKV_AWS_144: Log bucket replication not required
  # checkov:skip=CKV2_AWS_62: Log bucket notifications not required
  bucket = "${var.environment}-${var.app_name}-logs"

  tags = {
    Environment = var.environment
    Application = var.app_name
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket_public_access_block" "log_bucket" {
  bucket                  = aws_s3_bucket.log_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Main application bucket
resource "aws_s3_bucket" "app_bucket" {
  # checkov:skip=CKV_AWS_144: Cross-region replication not required for this environment
  # checkov:skip=CKV2_AWS_62: Event notifications not required for this environment
  bucket = "${var.environment}-${var.app_name}-bucket"

  tags = {
    Environment = var.environment
    Application = var.app_name
    ManagedBy   = "terraform"
  }
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "app_bucket" {
  bucket                  = aws_s3_bucket.app_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning
resource "aws_s3_bucket_versioning" "app_bucket" {
  bucket = aws_s3_bucket.app_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Enable KMS encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "app_bucket" {
  bucket = aws_s3_bucket.app_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3_key.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

# Enable access logging
resource "aws_s3_bucket_logging" "app_bucket" {
  bucket        = aws_s3_bucket.app_bucket.id
  target_bucket = aws_s3_bucket.log_bucket.id
  target_prefix = "s3-access-logs/"
}

# Lifecycle policy
resource "aws_s3_bucket_lifecycle_configuration" "app_bucket" {
  bucket = aws_s3_bucket.app_bucket.id
  rule {
    id     = "expire-old-versions"
    status = "Enabled"
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}