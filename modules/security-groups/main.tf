################################################################################
# modules/security-groups/main.tf (FIXED - no circular dependency)
################################################################################

##############################
# Load Balancer Security Group
##############################
resource "aws_security_group" "lb" {
  name        = "${var.environment}-k8s-lb-sg"
  description = "Security group for Kubernetes API load balancer"
  vpc_id      = var.vpc_id

  ingress {
    description = "Kubernetes API from anywhere"
    from_port   = 6443
    to_port     = 6443
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
    Name        = "${var.environment}-k8s-lb-sg"
    Environment = var.environment
  }
}

##############################
# Master Nodes Security Group
##############################
resource "aws_security_group" "master" {
  name        = "${var.environment}-k8s-master-sg"
  description = "Security group for Kubernetes master nodes"
  vpc_id      = var.vpc_id

  # SSH access
  ingress {
    description = "SSH from allowed IPs"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_ips
  }

  # Kubernetes API from load balancer
  ingress {
    description     = "Kubernetes API from load balancer"
    from_port       = 6443
    to_port         = 6443
    protocol        = "tcp"
    security_groups = [aws_security_group.lb.id]
  }

  # Allow internal master communication
  ingress {
    description = "All traffic between masters"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # etcd, kubelet, scheduler, controller ports
  dynamic "ingress" {
    for_each = [
      { desc = "etcd server client API", from = 2379, to = 2380 },
      { desc = "Kubelet API", from = 10250, to = 10250 },
      { desc = "kube-scheduler", from = 10259, to = 10259 },
      { desc = "kube-controller-manager", from = 10257, to = 10257 },
      { desc = "Calico BGP", from = 179, to = 179 },
    ]
    content {
      description = ingress.value.desc
      from_port   = ingress.value.from
      to_port     = ingress.value.to
      protocol    = "tcp"
      self        = true
    }
  }

  # Calico VXLAN
  ingress {
    description = "Calico VXLAN"
    from_port   = 4789
    to_port     = 4789
    protocol    = "udp"
    self        = true
  }

  # NodePort Services
  ingress {
    description = "NodePort Services"
    from_port   = 30000
    to_port     = 32767
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
    Name        = "${var.environment}-k8s-master-sg"
    Environment = var.environment
  }
}

##############################
# Worker Nodes Security Group
##############################
resource "aws_security_group" "worker" {
  name        = "${var.environment}-k8s-worker-sg"
  description = "Security group for Kubernetes worker nodes"
  vpc_id      = var.vpc_id

  # SSH access
  ingress {
    description = "SSH from allowed IPs"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_ips
  }

  # Worker-to-worker traffic
  ingress {
    description = "All traffic between workers"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # NodePort services
  ingress {
    description = "NodePort Services"
    from_port   = 30000
    to_port     = 32767
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
    Name        = "${var.environment}-k8s-worker-sg"
    Environment = var.environment
  }
}

##############################
# FIXED CROSS-SECURITY-GROUP RULES
##############################

# Masters ↔ Workers traffic (split into separate aws_security_group_rule resources)
resource "aws_security_group_rule" "master_to_worker" {
  description              = "Allow all traffic from masters to workers"
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  security_group_id        = aws_security_group.worker.id
  source_security_group_id = aws_security_group.master.id
}

resource "aws_security_group_rule" "worker_to_master" {
  description              = "Allow all traffic from workers to masters"
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  security_group_id        = aws_security_group.master.id
  source_security_group_id = aws_security_group.worker.id
}

################################################################################
# modules/security-groups/variables.tf
################################################################################

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "allowed_ssh_ips" {
  description = "CIDR blocks allowed to SSH"
  type        = list(string)
}

################################################################################
# modules/security-groups/outputs.tf
################################################################################

output "lb_security_group_id" {
  description = "Load balancer security group ID"
  value       = aws_security_group.lb.id
}

output "master_security_group_id" {
  description = "Master nodes security group ID"
  value       = aws_security_group.master.id
}

output "worker_security_group_id" {
  description = "Worker nodes security group ID"
  value       = aws_security_group.worker.id
}