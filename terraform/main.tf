provider "aws" {
  region = var.region
}

# Get default VPC
data "aws_vpc" "default" {
  default = true
}

# 1.a Read-only S3 Role & Policy
resource "aws_iam_role" "s3_readonly_role_v4" {
  name = "s3-readonly-role-unique-2025-08-10-v4"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "s3_readonly_policy_v4" {
  name = "s3-readonly-policy-unique-2025-08-10-v4"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["s3:ListBucket"]
      Resource = "arn:aws:s3:::${var.bucket_name}"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "s3_readonly_attach_v4" {
  role       = aws_iam_role.s3_readonly_role_v4.name
  policy_arn = aws_iam_policy.s3_readonly_policy_v4.arn
}

# 1.b Write-only Role (no read/download)
resource "aws_iam_role" "s3_writeonly_role_v4" {
  name = "s3-writeonly-role-unique-2025-08-10-v4"
  assume_role_policy = aws_iam_role.s3_readonly_role_v4.assume_role_policy
}

resource "aws_iam_policy" "s3_writeonly_policy_v4" {
  name = "s3-writeonly-policy-unique-2025-08-10-v4"
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

resource "aws_iam_role_policy_attachment" "s3_writeonly_attach_v4" {
  role       = aws_iam_role.s3_writeonly_role_v4.name
  policy_arn = aws_iam_policy.s3_writeonly_policy_v4.arn
}

# 2. Instance profile for EC2 with write-only role
resource "aws_iam_instance_profile" "ec2_instance_profile_v4" {
  name = "ec2-instance-profile-unique-2025-08-10-v4"
  role = aws_iam_role.s3_writeonly_role_v4.name
}

# 3. Create private S3 bucket with lifecycle policy
resource "aws_s3_bucket" "log_bucket" {
  bucket        = var.bucket_name
  force_destroy = true

  tags = {
    Name = var.bucket_name
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "log_lifecycle" {
  bucket = aws_s3_bucket.log_bucket.id

  rule {
    id     = "delete-logs-after-7-days"
    status = "Enabled"

    filter {
      prefix = "" # applies to all objects
    }

    expiration {
      days = 7
    }
  }
}

# 4. Security Group allowing SSH and HTTP on default VPC
resource "aws_security_group" "ec2_sg" {
  name        = "ec2-security-group-unique-2025-08-10"
  description = "Allow SSH and HTTP inbound traffic"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "EC2 Security Group"
  }
}

# 5. EC2 instance with write-only IAM role and attached security group
resource "aws_instance" "ec2_instance" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = var.ec2_key_name
  iam_instance_profile        = aws_iam_instance_profile.ec2_instance_profile_v4.name
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]

  tags = {
    Name = "WriteOnlyEC2-unique-2025-08-10-v4"
  }
}
