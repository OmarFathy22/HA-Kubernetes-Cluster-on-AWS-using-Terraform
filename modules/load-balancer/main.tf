################################################################################
# modules/load-balancer/main.tf
################################################################################

resource "aws_lb" "k8s_api" {
  name               = "${var.environment}-k8s-api-lb"
  internal           = false
  load_balancer_type = "network"
  subnets            = var.public_subnet_ids

  enable_deletion_protection       = false
  enable_cross_zone_load_balancing = true

  tags = {
    Name        = "${var.environment}-k8s-api-lb"
    Environment = var.environment
  }
}

resource "aws_lb_target_group" "k8s_api" {
  name     = "${var.environment}-k8s-api-tg"
  port     = 6443
  protocol = "TCP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    interval            = 10
    port                = 6443
    protocol            = "TCP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  deregistration_delay = 30

  tags = {
    Name        = "${var.environment}-k8s-api-tg"
    Environment = var.environment
  }
}

resource "aws_lb_listener" "k8s_api" {
  load_balancer_arn = aws_lb.k8s_api.arn
  port              = 6443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.k8s_api.arn
  }

  tags = {
    Name        = "${var.environment}-k8s-api-listener"
    Environment = var.environment
  }
}

################################################################################
# modules/load-balancer/variables.tf
################################################################################

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs"
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security group IDs for the load balancer"
  type        = list(string)
  default     = []
}

################################################################################
# modules/load-balancer/outputs.tf
################################################################################

output "lb_arn" {
  description = "Load balancer ARN"
  value       = aws_lb.k8s_api.arn
}

output "lb_dns_name" {
  description = "Load balancer DNS name"
  value       = aws_lb.k8s_api.dns_name
}

output "lb_zone_id" {
  description = "Load balancer zone ID"
  value       = aws_lb.k8s_api.zone_id
}

output "target_group_arn" {
  description = "Target group ARN"
  value       = aws_lb_target_group.k8s_api.arn
}