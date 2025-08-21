provider "aws" {
  region = var.region
}

data "aws_vpc" "default" {
  default = true
}

# ---------- IAM Roles & Policies ----------

resource "aws_iam_role" "s3_readonly_role" {
  name = "s3-readonly-role-${var.stage}"
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
  name = "s3-readonly-policy-${var.stage}"
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

resource "aws_iam_role" "s3_writeonly_role" {
  name = "s3-writeonly-role-${var.stage}"
  assume_role_policy = aws_iam_role.s3_readonly_role.assume_role_policy
}

resource "aws_iam_policy" "s3_writeonly_policy" {
  name = "s3-writeonly-policy-${var.stage}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
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
    }]
  })
}

resource "aws_iam_role_policy_attachment" "s3_writeonly_attach" {
  role       = aws_iam_role.s3_writeonly_role.name
  policy_arn = aws_iam_policy.s3_writeonly_policy.arn
}

resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "ec2-instance-profile-${var.stage}"
  role = aws_iam_role.s3_writeonly_role.name
}

# ---------- S3 Bucket ----------

resource "aws_s3_bucket" "log_bucket" {
  bucket        = var.bucket_name
  force_destroy = true

  tags = {
    Name  = var.bucket_name
    Stage = var.stage
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "log_lifecycle" {
  bucket = aws_s3_bucket.log_bucket.id

  rule {
    id     = "delete-logs-after-7-days"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = 7
    }
  }
}

# ---------- Security Group ----------

resource "aws_security_group" "ec2_sg" {
  name        = "ec2-sg-${var.stage}"
  description = "Allow SSH and HTTP"
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
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name  = "EC2 Security Group - ${var.stage}"
    Stage = var.stage
  }
}

# ---------- EC2 Instance ----------

resource "aws_instance" "ec2_instance" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = var.ec2_key_name
  iam_instance_profile        = aws_iam_instance_profile.ec2_instance_profile.name
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]

  tags = {
    Name  = "WriteOnlyEC2-${var.stage}"
    Stage = var.stage
  }
}
