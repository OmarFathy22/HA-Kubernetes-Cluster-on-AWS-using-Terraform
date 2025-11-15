
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