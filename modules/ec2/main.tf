################################################################################
# modules/ec2/main.tf
################################################################################

# Data source for latest Ubuntu 22.04 AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# User data script for master nodes
# data "template_file" "master_user_data" {
#   template = file("${path.module}/scripts/master-init.sh")
# }

# # User data script for worker nodes
# data "template_file" "worker_user_data" {
#   template = file("${path.module}/scripts/worker-init.sh")
# }

# Master Nodes
resource "aws_instance" "master" {
  count                  = var.master_count
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.master_instance_type
  key_name               = var.key_name
  subnet_id              = var.public_subnet_ids[count.index % length(var.public_subnet_ids)]
  vpc_security_group_ids = var.master_security_group_ids
#   user_data              = data.template_file.master_user_data.rendered

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = {
    Name        = "${var.environment}-k8s-master-${count.index + 1}"
    Environment = var.environment
    Role        = "master"
    "kubernetes.io/cluster/${var.environment}" = "owned"
  }
}

# Worker Nodes
resource "aws_instance" "worker" {
  count                  = var.worker_count
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.worker_instance_type
  key_name               = var.key_name
  subnet_id              = var.public_subnet_ids[count.index % length(var.public_subnet_ids)]
  vpc_security_group_ids = var.worker_security_group_ids
#   user_data              = data.template_file.worker_user_data.rendered

  root_block_device {
    volume_size           = 50
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = {
    Name        = "${var.environment}-k8s-worker-${count.index + 1}"
    Environment = var.environment
    Role        = "worker"
    "kubernetes.io/cluster/${var.environment}" = "owned"
  }
}

# Attach master nodes to load balancer target group
resource "aws_lb_target_group_attachment" "master" {
  count            = var.master_count
  target_group_arn = var.lb_target_group_arn
  target_id        = aws_instance.master[count.index].id
  port             = 6443
}

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

################################################################################
# modules/ec2/outputs.tf
################################################################################

output "master_instance_ids" {
  description = "Master node instance IDs"
  value       = aws_instance.master[*].id
}

output "master_private_ips" {
  description = "Master node private IPs"
  value       = aws_instance.master[*].private_ip
}

output "master_public_ips" {
  description = "Master node public IPs"
  value       = aws_instance.master[*].public_ip
}

output "worker_instance_ids" {
  description = "Worker node instance IDs"
  value       = aws_instance.worker[*].id
}

output "worker_private_ips" {
  description = "Worker node private IPs"
  value       = aws_instance.worker[*].private_ip
}

output "worker_public_ips" {
  description = "Worker node public IPs"
  value       = aws_instance.worker[*].public_ip
}