# ========== LOCALS ============================================================

# Define defaults, then merge per-environment variables as described in https://github.com/hashicorp/terraform/issues/15966
locals {
  default_file               = "./group_vars/all/main.yml"
  default_content            = fileexists(local.default_file) ? file(local.default_file) : "NoSettingsFileFound: true"
  default_vars               = yamldecode(local.default_content)
  env_file                   = "./group_vars/${terraform.workspace}/main.yml"
  env_content                = fileexists(local.env_file) ? file(local.env_file) : "NoSettingsFileFound: true"
  env_vars                   = yamldecode(local.env_content)
  root                       = merge(local.default_vars, local.env_vars,
                                     { private_zone: "${terraform.workspace}.local",
                                       ec2_env: terraform.workspace } )
}


# ========== PROVIDERS =========================================================

terraform {
  backend "s3" {
    bucket         = "cloudadmin.markerbench.com"
    workspace_key_prefix = "terraform"
    key            = "terraform.tfstate"
    region         = "us-east-1"
  }
}

provider "aws" { 
  profile = "default"
  region = local.root.ec2_region
}


# ========== DATA SOURCES (looked up by ID) ====================================

data "aws_route53_zone" "public" {
  name             = "${local.root.public_domain}."
  private_zone     = false
}


# ========== MODULES ===========================================================

# Virtual private cloud (VPC) and subnets
module "vpc" {
  source           = "./modules/vpc"
  root             = local.root
}

# IAM roles and policies
module "roles" {
  source           = "./modules/roles"
  root             = local.root
  cluster          = module.services.cluster_arn
  secrets          = module.secrets.secrets
}

# Secrets
module "secrets" {
  source           = "./modules/secrets"
  root             = local.root
}

# Elastic File System (EFS) service
module "efs" {
  source           = "./modules/efs"
  root             = local.root
  vpc_id           = module.vpc.vpc_id
  subnet_ids       = module.vpc.subnet_ids
  subnet_blocks    = module.vpc.subnet_blocks
}

# EC2 Instances
module "instances" {
  source           = "./modules/instances"
  root             = local.root
  vpc_id           = module.vpc.vpc_id
  subnet_ids       = module.vpc.subnet_ids
  efs_id           = module.efs.id
  instance_profile = module.roles.iam_instance_profile
}

# Elastic Container Service (ECS) tasks and services
module "services" {
  source           = "./modules/services"
  root             = local.root
  vpc_id           = module.vpc.vpc_id
  subnet_blocks    = module.vpc.subnet_blocks
  private_ips      = module.instances.private_ips
  execution_role   = module.roles.execution_role_arn
  secrets          = module.secrets.secrets
}


# ========== OUTPUT VARIABLES ==================================================

output "public_ips" {
  description      = "Public IP addresses"
  value            = module.instances.public_ips
}

output "private_ips" {
  description      = "Private IP addresses"
  value            = module.instances.private_ips
}

output "efs_id" {
  description      = "Elastic File Service ID"
  value            = module.efs.id
}

output "ec2_env" {
  description      = "EC2 environment, aka terraform workspace"
  value            = local.root.ec2_env
}
