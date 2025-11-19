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

################################################################################
# CLOUD-INIT USER DATA FOR MASTER NODES
################################################################################
# data "cloudinit_config" "master_user_data" {
#   count         = var.master_count
#   gzip          = true
#   base64_encode = true

#   # Part 1: Common initialization (runs on all nodes)
#   part {
#     content_type = "text/x-shellscript"
#     content = templatefile("${path.module}/scripts/common-init.sh", {
#       HOSTNAME         = "${var.environment}-k8s-master-${count.index + 1}"
#       IS_LEADER        = tostring(count.index == 0)
#       LB_DNS           = var.load_balancer_dns
#       BOOTSTRAP_BUCKET = var.bootstrap_s3_bucket
#     })
#   }

#   # Part 2: Master-specific initialization
#   part {
#     content_type = "text/x-shellscript"
#     content = templatefile("${path.module}/scripts/master-init.sh", {
#       HOSTNAME         = "${var.environment}-k8s-master-${count.index + 1}"
#       IS_LEADER        = tostring(count.index == 0)
#       LB_DNS           = var.load_balancer_dns
#       BOOTSTRAP_BUCKET = var.bootstrap_s3_bucket
#     })
#   }
# }

################################################################################
# CLOUD-INIT USER DATA FOR WORKER NODES
################################################################################
# data "cloudinit_config" "worker_user_data" {
#   count         = var.worker_count
#   gzip          = true
#   base64_encode = true

#   # Part 1: Common initialization (runs on all nodes)
#   part {
#     content_type = "text/x-shellscript"
#     content = templatefile("${path.module}/scripts/common-init.sh", {
#       HOSTNAME         = "${var.environment}-k8s-worker-${count.index + 1}"
#       IS_LEADER        = "false"
#       LB_DNS           = var.load_balancer_dns
#       BOOTSTRAP_BUCKET = var.bootstrap_s3_bucket
#     })
#   }

  # Part 2: Worker-specific initialization
#   part {
#     content_type = "text/x-shellscript"
#     content = templatefile("${path.module}/scripts/worker-init.sh", {
#       HOSTNAME         = "${var.environment}-k8s-worker-${count.index + 1}"
#       LB_DNS           = var.load_balancer_dns
#       BOOTSTRAP_BUCKET = var.bootstrap_s3_bucket
#     })
#   }
# }

################################################################################
# MASTER NODES
################################################################################
resource "aws_instance" "master" {
  count                  = var.master_count
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.master_instance_type
  key_name               = var.key_name
  subnet_id              = var.public_subnet_ids[count.index % length(var.public_subnet_ids)]
  vpc_security_group_ids = var.master_security_group_ids
  # user_data              = data.cloudinit_config.master_user_data[count.index].rendered
  iam_instance_profile   = var.iam_instance_profile_name

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
    IsLeader    = tostring(count.index == 0)
    "kubernetes.io/cluster/${var.environment}" = "owned"
  }

  # Add a small delay between master launches to avoid race conditions
  depends_on = [
    # Masters depend on nothing but will launch in order due to count
  ]
}

################################################################################
# WORKER NODES
################################################################################
resource "aws_instance" "worker" {
  count                  = var.worker_count
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.worker_instance_type
  key_name               = var.key_name
  subnet_id              = var.public_subnet_ids[count.index % length(var.public_subnet_ids)]
  vpc_security_group_ids = var.worker_security_group_ids
  # user_data              = data.cloudinit_config.worker_user_data[count.index].rendered
  iam_instance_profile   = var.iam_instance_profile_name

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
    Name        = "${var.environment}-k8s-worker-${count.index + 1}"
    Environment = var.environment
    Role        = "worker"
    "kubernetes.io/cluster/${var.environment}" = "owned"
  }

  # Workers should launch after masters start (not wait for completion)
  depends_on = [
    aws_instance.master
  ]
}

################################################################################
# ATTACH MASTER NODES TO LOAD BALANCER TARGET GROUP
################################################################################
resource "aws_lb_target_group_attachment" "master" {
  count            = var.master_count
  target_group_arn = var.lb_target_group_arn
  target_id        = aws_instance.master[count.index].id
  port             = 6443
}

