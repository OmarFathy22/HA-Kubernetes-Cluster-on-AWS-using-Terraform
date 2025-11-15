terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "k8s-ha-cluster"
      ManagedBy   = "terraform"
    }
  }
}


module "vpc" {
  source = "./modules/vpc"

  environment         = var.environment
  vpc_cidr            = var.vpc_cidr
  availability_zones  = var.availability_zones
  public_subnet_cidrs = var.public_subnet_cidrs
}



module "security_groups" {
  source = "./modules/security-groups"

  environment     = var.environment
  vpc_id          = module.vpc.vpc_id
  allowed_ssh_ips = var.allowed_ssh_ips
}


module "load_balancer" {
  source = "./modules/load-balancer"

  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  security_group_ids = [module.security_groups.lb_security_group_id]
}



module "ec2_instances" {
  source = "./modules/ec2"

  environment               = var.environment
  public_subnet_ids         = module.vpc.public_subnet_ids
  master_security_group_ids = [module.security_groups.master_security_group_id]
  worker_security_group_ids = [module.security_groups.worker_security_group_id]
  key_name                  = var.key_name
  master_instance_type      = var.master_instance_type
  worker_instance_type      = var.worker_instance_type
  master_count              = var.master_count
  worker_count              = var.worker_count
  lb_target_group_arn       = module.load_balancer.target_group_arn
  load_balancer_dns         = module.load_balancer.lb_dns_name
  bootstrap_s3_bucket       = aws_s3_bucket.k8s_bootstrap.bucket
  iam_instance_profile_name = aws_iam_instance_profile.ec2_profile.name
}

# S3 bucket for bootstrap artifacts (kubeadm token, cert key)
resource "aws_s3_bucket" "k8s_bootstrap" {
  bucket = "${var.environment}-k8s-bootstrap-${random_id.bucket_id.hex}"

  tags = {
    Name        = "${var.environment}-k8s-bootstrap"
    Environment = var.environment
  }
}

resource "random_id" "bucket_id" {
  byte_length = 4
}

# IAM role and instance profile for EC2 instances to access S3
resource "aws_iam_role" "ec2_role" {
  name = "${var.environment}-ec2-s3-role"

  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role_policy.json
}

data "aws_iam_policy_document" "ec2_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "s3_read_write" {
  name        = "${var.environment}-ec2-s3-bootstrap-policy"
  description = "Allow EC2 instances to get/put bootstrap artifacts in S3"

  policy = data.aws_iam_policy_document.s3_policy.json
}

data "aws_iam_policy_document" "s3_policy" {
  statement {
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.k8s_bootstrap.arn,
      "${aws_s3_bucket.k8s_bootstrap.arn}/*",
    ]
  }
}

resource "aws_iam_role_policy_attachment" "attach_s3_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.s3_read_write.arn
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.environment}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}



