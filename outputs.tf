################################################################################
# Outputs
################################################################################

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "load_balancer_dns" {
  description = "Load balancer DNS name"
  value       = module.load_balancer.lb_dns_name
}

output "load_balancer_arn" {
  description = "Load balancer ARN"
  value       = module.load_balancer.lb_arn
}

output "master_instance_ids" {
  description = "Master node instance IDs"
  value       = module.ec2_instances.master_instance_ids
}

output "master_private_ips" {
  description = "Master node private IPs"
  value       = module.ec2_instances.master_private_ips
}

output "master_public_ips" {
  description = "Master node public IPs"
  value       = module.ec2_instances.master_public_ips
}

output "worker_instance_ids" {
  description = "Worker node instance IDs"
  value       = module.ec2_instances.worker_instance_ids
}

output "worker_private_ips" {
  description = "Worker node private IPs"
  value       = module.ec2_instances.worker_private_ips
}

output "worker_public_ips" {
  description = "Worker node public IPs"
  value       = module.ec2_instances.worker_public_ips
}
