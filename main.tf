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
  region = local.vars.ec2_region
}

# ========== DATA SOURCES (looked up by ID) ====================================

data "aws_iam_user" "cloudadmin" {
  user_name        = "cloudadmin"
}

data "aws_iam_group" "cloudadmins" {
  group_name       = "Cloudadmins"
}

data "aws_route53_zone" "public" {
  name             = "${local.vars.public_domain}."
  private_zone     = false
}

# ========== RESOURCES =========================================================

## --------- Virtual private cloud ---------------------------------------------

module "vpc" {
  source           = "./modules/vpc"
  root             = local.vars
}

## --------- Security groups ---------------------------------------------------

resource "aws_security_group" "public" {
  for_each         = local.vars.security_groups["public"]
  name             = "${terraform.workspace}-${each.key}-public"
  description      = each.value.description
  vpc_id           = module.vpc.vpc_id
  dynamic "ingress" {
    for_each       = each.value.ports
    content {
      from_port    = ingress.value
      to_port      = ingress.value
      protocol     = "tcp"
      cidr_blocks  = [module.vpc.any_cidr_block]
    }
  }
  egress {
    description    = "All IPv4"
    from_port      = 0
    to_port        = 0
    protocol       = "-1"
    cidr_blocks    = [module.vpc.any_cidr_block]
  }
  tags = {
    Name           = "${terraform.workspace}-${each.key}-public"
    Environment    = terraform.workspace
  }
}

resource "aws_security_group" "private" {
  for_each         = local.vars.security_groups["private"]
  name             = "${terraform.workspace}-${each.key}-private"
  description      = each.value.description
  vpc_id           = module.vpc.vpc_id
  dynamic "ingress" {
    for_each       = each.value.ports
    content {
      from_port    = ingress.value
      to_port      = ingress.value
      protocol     = "tcp"
      cidr_blocks  = values(module.vpc.subnet_cidr_blocks)
    }
  }
  egress {
    description    = "Any subnet"
    from_port      = 0
    to_port        = 0
    protocol       = "-1"
    cidr_blocks    = values(module.vpc.subnet_cidr_blocks)
  }
  tags = {
    Name           = "${terraform.workspace}-${each.key}-private"
    Environment    = terraform.workspace
  }
}

## --------- Roles and policies ------------------------------------------------

module "roles" {
  source           = "./modules/roles"
  secrets          = module.secrets.secrets
}

## --------- Keys and secrets --------------------------------------------------

resource "aws_key_pair" "production" {
  key_name         = local.vars.ec2_ssh_key_name
  public_key       = file("${local.vars.ec2_ssh_key}")
}

module "secrets" {
  source           = "./modules/secrets"
  root             = local.vars
}

## --------- NFS shared storage ------------------------------------------------

resource "aws_efs_file_system" "nfs" {
  creation_token   = "nfs"
  tags = {
    Name           = "${terraform.workspace}-nfs"
    Environment    = terraform.workspace
  }
}

resource "aws_efs_mount_target" "nfs" {
  for_each = module.vpc.subnet_ids
  file_system_id   = aws_efs_file_system.nfs.id
  subnet_id        = each.value
  security_groups  = [aws_security_group.private["nfs"].id]
}

## --------- ECS cluster -------------------------------------------------------

resource "aws_ecs_cluster" "ecs" {
  name = "${terraform.workspace}"
  tags = {
    Name         = "ecs"
    Environment  = terraform.workspace
  }
}

resource "aws_ecs_task_definition" "postgres" {
  family                     = "postgres"
  container_definitions      = templatefile("etc/tasks/postgres.json",
                                            merge(local.vars, { secrets: module.secrets.secrets }))
  execution_role_arn         = module.roles.execution_role_arn
  network_mode               = "host"
  memory                     = "256"
  volume {
    name                     = "postgres_data"
    host_path                = local.vars.postgres_data
  }
  requires_compatibilities   = [ "EC2" ]
  tags = {
    Name                     = "${terraform.workspace}-postgres"
    Environment              = terraform.workspace
  }
}

resource "aws_ecs_service" "postgres" {
  name                       = "postgres"
  task_definition            = aws_ecs_task_definition.postgres.arn
  launch_type                = "EC2"
  scheduling_strategy        = "REPLICA"
  desired_count              = 1
  cluster                    = aws_ecs_cluster.ecs.arn
  ordered_placement_strategy {
    type                     = "binpack"
    field                    = "memory"
  }
  placement_constraints {
    type                     = "memberOf"
    expression               = "attribute:Role == 'mail'"
  }
  lifecycle {
    ignore_changes           = ["desired_count"]
  }
  tags = {
    Name                     = "${terraform.workspace}-postgres"
    Environment              = terraform.workspace
  }
}

resource "aws_ecs_task_definition" "mailman-core" {
  family                     = "mailman-core"
  container_definitions      = templatefile("etc/tasks/mailman-core.json",
                                            merge(local.vars, { secrets: module.secrets.secrets }))
  execution_role_arn         = module.roles.execution_role_arn
  network_mode               = "host"
  memory                     = "256"
  volume {
    name                     = "mailman_core"
    host_path                = local.vars.mailman_core
  }
  requires_compatibilities   = [ "EC2" ]
  tags = {
    Name                     = "${terraform.workspace}-mailman-core"
    Environment              = terraform.workspace
  }
}

## --------- Instances ---------------------------------------------------------

resource "aws_instance" "www" {
  depends_on       = [aws_efs_mount_target.nfs]
  key_name         = local.vars.ec2_ssh_key_name
  ami              = local.vars.ec2_instance_ami
  instance_type    = local.vars.ec2_instance_type
  iam_instance_profile = module.roles.iam_instance_profile
  vpc_security_group_ids = [aws_security_group.public["ssh"].id,
                      aws_security_group.public["https"].id,
                      aws_security_group.private["mailman-web"].id]
  monitoring       = true
  subnet_id        = module.vpc.subnet_ids["subnet1"]
  associate_public_ip_address = true
  tags = {
    Name           = "${terraform.workspace}-www"
    Environment    = terraform.workspace
    Role           = "www"
    EfsVolume      = aws_efs_file_system.nfs.id
  }
  volume_tags = {
    Name           = "${terraform.workspace}-www"
    Environment    = terraform.workspace
    Role           = "www"
  }
  user_data        = file("roles/base/templates/ec2_init.sh")
}

resource "aws_instance" "mail" {
  depends_on       = [aws_efs_mount_target.nfs]
  key_name         = local.vars.ec2_ssh_key_name
  ami              = local.vars.ec2_instance_ami
  instance_type    = local.vars.ec2_instance_type
  iam_instance_profile = module.roles.iam_instance_profile
  vpc_security_group_ids = [aws_security_group.public["ssh"].id,
                      aws_security_group.public["smtp"].id,
                      aws_security_group.private["postgres"].id,
                      aws_security_group.private["mailman-core"].id]
  monitoring       = true
  subnet_id        = module.vpc.subnet_ids["subnet2"]
  associate_public_ip_address = true
  tags = {
    Name           = "${terraform.workspace}-mail"
    Environment    = terraform.workspace
    Role           = "mail"
    EfsVolume      = aws_efs_file_system.nfs.id
  }
  volume_tags = {
    Name           = "${terraform.workspace}-mail"
    Environment    = terraform.workspace
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
  name             = "${each.key}.${local.vars.private_zone}"
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
            ${local.vars.ansible_playbook}
        EOT
  }
}
