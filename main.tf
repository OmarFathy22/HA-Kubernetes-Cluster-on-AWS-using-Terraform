terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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
}



