provider "aws" {
  region = var.region
}

# 1.a Read-only S3 Role
resource "aws_iam_role" "s3_readonly_role" {
  name = "s3-readonly-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "s3_readonly_policy" {
  name = "s3-readonly-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["s3:ListBucket"]
      Resource = "arn:aws:s3:::${var.bucket_name}"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "s3_readonly_attach" {
  role       = aws_iam_role.s3_readonly_role.name
  policy_arn = aws_iam_policy.s3_readonly_policy.arn
}

# 1.b Write-only Role (no read/download)
resource "aws_iam_role" "s3_writeonly_role" {
  name = "s3-writeonly-role"
  assume_role_policy = aws_iam_role.s3_readonly_role.assume_role_policy
}

resource "aws_iam_policy" "s3_writeonly_policy" {
  name = "s3-writeonly-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:CreateBucket",
          "s3:PutBucketPolicy"
        ]
        Resource = [
          "arn:aws:s3:::${var.bucket_name}",
          "arn:aws:s3:::${var.bucket_name}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "s3_writeonly_attach" {
  role       = aws_iam_role.s3_writeonly_role.name
  policy_arn = aws_iam_policy.s3_writeonly_policy.arn
}

# 2. Instance profile for EC2
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "ec2-instance-profile"
  role = aws_iam_role.s3_writeonly_role.name
}

# 3. Create private S3 bucket (no lifecycle here)
resource "aws_s3_bucket" "log_bucket" {
  bucket         = var.bucket_name
  force_destroy  = true

  tags = {
    Name = var.bucket_name
  }
}

# 3.b Apply lifecycle policy separately
resource "aws_s3_bucket_lifecycle_configuration" "log_lifecycle" {
  bucket = aws_s3_bucket.log_bucket.id

  rule {
    id     = "delete-logs-after-7-days"
    status = "Enabled"

    filter {
      prefix = "" # Applies to all objects
    }

    expiration {
      days = 7
    }
  }
}

# 4. EC2 instance with write-only role
resource "aws_instance" "ec2_instance" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = var.ec2_key_name
  iam_instance_profile        = aws_iam_instance_profile.ec2_instance_profile.name
  associate_public_ip_address = true

  tags = {
    Name = "WriteOnlyEC2"
  }
}
