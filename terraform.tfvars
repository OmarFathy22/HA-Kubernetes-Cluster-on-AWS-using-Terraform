aws_region           = "us-east-1"
environment          = "production"
key_name             = "k8s-cluster-key"
allowed_ssh_ips      = ["0.0.0.0/0"]
master_instance_type = "t3.small"
worker_instance_type = "t3.small"