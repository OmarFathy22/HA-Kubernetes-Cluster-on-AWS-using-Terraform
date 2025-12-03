################################################################################
# Root variables.tf
################################################################################

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "allowed_ssh_ips" {
  description = "CIDR blocks allowed to SSH"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Change this to your IP for security
}

variable "key_name" {
  description = "EC2 key pair name"
  type        = string
  default = "k8s-cluster-key"
}

variable "master_instance_type" {
  description = "Master node instance type"
  type        = string
  default     = "t3.small"
}

variable "worker_instance_type" {
  description = "Worker node instance type"
  type        = string
  default     = "t3.small"
}

variable "master_count" {
  description = "Number of master nodes"
  type        = number
  default     = 3
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2
}