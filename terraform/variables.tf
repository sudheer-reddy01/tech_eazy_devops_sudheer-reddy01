variable "region" {
  description = "AWS region to deploy resources in"
  type        = string
  default     = "us-east-1"
}

variable "bucket_name" {
  description = "Name of the private S3 bucket"
  type        = string
}

variable "ec2_key_name" {
  description = "Name of the EC2 key pair"
  type        = string
}

variable "ami_id" {
  description = "AMI ID to use for EC2 instance"
  type        = string
  default     = "ami-053b0d53c279acc90" # Amazon Linux 2
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
}

variable "stage" {
  description = "Deployment stage (e.g., dev, prod)"
  type        = string
  default     = "dev"
}
