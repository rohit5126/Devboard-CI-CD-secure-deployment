output "bucket_name" {
  description = "Name of the S3 bucket holding the main config's state"
  value       = aws_s3_bucket.tf_state.id
}