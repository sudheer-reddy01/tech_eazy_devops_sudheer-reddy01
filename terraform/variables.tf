variable "region" {
  default = "us-east-1"
}

variable "bucket_name" {
  description = "Name of the private S3 bucket"
  type        = string
  validation {
    condition     = length(var.bucket_name) > 0
    error_message = "Bucket name must be provided."
  }
}

variable "ec2_key_name" {
  description = "EC2 key pair name"
  type        = string
}

variable "ami_id" {
  default = "ami-053b0d53c279acc90" # Amazon Linux 2
}

variable "instance_type" {
  default = "t2.micro"
}
