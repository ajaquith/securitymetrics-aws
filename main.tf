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
  subnet_cidr_blocks = module.vpc.subnet_cidr_blocks
}

# Elastic Container Service (ECS) tasks and services
module "services" {
  source           = "./modules/services"
  root             = local.root
  vpc_id           = module.vpc.vpc_id
  subnet_cidr_blocks = module.vpc.subnet_cidr_blocks
  any_cidr_block   = module.vpc.any_cidr_block
  execution_role   = module.roles.execution_role_arn
  secrets          = module.secrets.secrets
}

# EC2 Instances
module "instances" {
  source           = "./modules/instances"
  root             = local.root
  vpc_id           = module.vpc.vpc_id
  subnet_ids       = module.vpc.subnet_ids
  any_cidr_block   = module.vpc.any_cidr_block
  instance_profile = module.roles.iam_instance_profile
}


# ========== RESOURCES =========================================================

## --------- Instances ---------------------------------------------------------

resource "aws_instance" "www" {
  depends_on       = [module.efs.id]
  key_name         = local.root.ec2_ssh_key_name
  ami              = local.root.ec2_instance_ami
  instance_type    = local.root.ec2_instance_type
  iam_instance_profile = module.roles.iam_instance_profile
  vpc_security_group_ids = [module.instances.ssh_security_group_id]
  monitoring       = true
  subnet_id        = module.vpc.subnet_ids["subnet1"]
  associate_public_ip_address = true
  tags = {
    Name           = "${local.root.ec2_env}-www"
    Environment    = local.root.ec2_env
    Role           = "www"
    EfsVolume      = module.efs.id
  }
  volume_tags = {
    Name           = "${local.root.ec2_env}-www"
    Environment    = local.root.ec2_env
    Role           = "www"
  }
  user_data        = file("roles/base/templates/ec2_init.sh")
}

resource "aws_instance" "mail" {
  depends_on       = [module.efs.id]
  key_name         = local.root.ec2_ssh_key_name
  ami              = local.root.ec2_instance_ami
  instance_type    = local.root.ec2_instance_type
  iam_instance_profile = module.roles.iam_instance_profile
  vpc_security_group_ids = [module.instances.ssh_security_group_id]
  monitoring       = true
  subnet_id        = module.vpc.subnet_ids["subnet2"]
  associate_public_ip_address = true
  tags = {
    Name           = "${local.root.ec2_env}-mail"
    Environment    = local.root.ec2_env
    Role           = "mail"
    EfsVolume      = module.efs.id
  }
  volume_tags = {
    Name           = "${local.root.ec2_env}-mail"
    Environment    = local.root.ec2_env
    Role           = "mail"
  }
  user_data        = file("roles/base/templates/ec2_init.sh")
}

resource "aws_route53_record" "private" {
  depends_on       = [aws_instance.www, aws_instance.mail]
  for_each         = { mailman-web:  aws_instance.www.private_ip,
                       mailman-core: aws_instance.mail.private_ip,
                       postfix:      aws_instance.mail.private_ip,
                       postgres:     aws_instance.mail.private_ip }
  zone_id          = module.vpc.private_zone_id
  name             = "${each.key}.${local.root.private_zone}"
  type             = "A"
  ttl              = "300"
  records          = [each.value]
  allow_overwrite  = true
}

resource "null_resource" "instances" {
  # Changes to any instance of the cluster requires re-provisioning
  triggers = {
    instance_ids = "${join(",", aws_instance.www.*.id, aws_instance.mail.*.id)}"
  }

  provisioner "local-exec" {
    command        = <<-EOT
        wait 30; \
        ansible-playbook \
            --ssh-extra-args='-o StrictHostKeyChecking=no' \
            ${local.root.ansible_playbook}
        EOT
  }
}
