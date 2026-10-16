output "bucket_name" {
  value = aws_s3_bucket.images.id
}

output "bucket_arn" {
  value = aws_s3_bucket.images.arn
}

output "bucket_region" {
  value = aws_s3_bucket.images.region
}
