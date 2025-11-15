################################################################################
# modules/ec2/variables.tf
################################################################################

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs"
  type        = list(string)
}

variable "master_security_group_ids" {
  description = "Security group IDs for master nodes"
  type        = list(string)
}

variable "worker_security_group_ids" {
  description = "Security group IDs for worker nodes"
  type        = list(string)
}

variable "key_name" {
  description = "EC2 key pair name"
  type        = string
}

variable "master_instance_type" {
  description = "Master node instance type"
  type        = string
  default     = "t3.medium"
}

variable "worker_instance_type" {
  description = "Worker node instance type"
  type        = string
  default     = "t3.medium"
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

variable "lb_target_group_arn" {
  description = "Load balancer target group ARN"
  type        = string
}

variable "load_balancer_dns" {
  description = "Load balancer DNS name used as control plane endpoint"
  type        = string
}

variable "bootstrap_s3_bucket" {
  description = "S3 bucket name where kubeadm join commands and certs will be stored"
  type        = string
}

variable "iam_instance_profile_name" {
  description = "IAM instance profile name to attach to EC2 instances for S3 access"
  type        = string
}


variable "TOKEN" {
  description = "Placeholder for kubeadm token (preserve literal $${TOKEN} in templates)"
  type        = string
  default     = "$${TOKEN}"
}

variable "CERT_KEY" {
  description = "Placeholder for kubeadm certificate key (preserve literal $${CERT_KEY})"
  type        = string
  default     = "$${CERT_KEY}"
}

variable "CA_HASH" {
  description = "Placeholder for CA hash (preserve literal $${CA_HASH})"
  type        = string
  default     = "$${CA_HASH}"
}
