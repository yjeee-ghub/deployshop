#############################
# S3 Bucket
#############################

resource "aws_s3_bucket" "images" {
  bucket = var.bucket_name

  force_destroy = false

  tags = {
    Name = "${var.project_name}-images"
  }
}


#############################
# S3 Versioning
#############################

resource "aws_s3_bucket_versioning" "images" {
  bucket = aws_s3_bucket.images.id

  versioning_configuration {
    status = "Enabled"
  }
}


#############################
# S3 Encryption
#############################

resource "aws_s3_bucket_server_side_encryption_configuration" "images" {
  bucket = aws_s3_bucket.images.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}


#############################
# S3 Public Access Block
#############################

resource "aws_s3_bucket_public_access_block" "images" {
  bucket = aws_s3_bucket.images.id

  block_public_acls  = true
  ignore_public_acls = true

  block_public_policy     = false
  restrict_public_buckets = false
}


#############################
# 상품 이미지 공개 읽기 정책
#############################

resource "aws_s3_bucket_policy" "product_images" {
  bucket = aws_s3_bucket.images.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "AllowPublicReadProductImages"
        Effect = "Allow"

        Principal = "*"

        Action = [
          "s3:GetObject"
        ]

        Resource = [
          "${aws_s3_bucket.images.arn}/products/*"
        ]
      }
    ]
  })

  depends_on = [
    aws_s3_bucket_public_access_block.images
  ]
}
