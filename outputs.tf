output "readonly_role_arn" {
  value = aws_iam_role.s3_readonly_role.arn
}

output "writeonly_role_arn" {
  value = aws_iam_role.s3_writeonly_role.arn
}

output "bucket_name" {
  value = aws_s3_bucket.log_bucket.id
}

output "ec2_public_ip" {
  value = aws_instance.ec2_instance.public_ip
}
