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

data "aws_iam_policy" "AmazonEC2ContainerServiceforEC2Role" {
  arn              = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

data "aws_iam_policy" "AmazonECSTaskExecutionRolePolicy" {
  arn              = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ========== RESOURCES =========================================================

## --------- Virtual Private Cloud (VPC) ---------------------------------------

resource "aws_internet_gateway" "default" {
  vpc_id           = aws_vpc.default.id
  tags = {
    Name           = terraform.workspace
    Environment    = terraform.workspace
  }
}

resource "aws_vpc" "default" {
  cidr_block                           = local.vars.ec2_vpc_cidr
  instance_tenancy                     = "default"
  enable_dns_support                   = true
  enable_dns_hostnames                 = true
  enable_classiclink                   = false
  enable_classiclink_dns_support       = false
  assign_generated_ipv6_cidr_block     = false
  tags = {
    Name           = terraform.workspace
    Environment    = terraform.workspace
  }
}

resource "aws_subnet" "subnets" {
  for_each = local.vars.subnets
  availability_zone                    = each.value.availability_zone
  cidr_block                           = each.value.cidr_block
  map_public_ip_on_launch              = false
  assign_ipv6_address_on_creation      = false
  vpc_id                               = aws_vpc.default.id
  tags = {
    Name                               = "${terraform.workspace}-${each.key}"
    Environment                        = terraform.workspace
  }
}

resource "aws_route" "internet" {
  route_table_id             = aws_vpc.default.default_route_table_id
  destination_cidr_block     = local.all_ipv4
  gateway_id                 = aws_internet_gateway.default.id
}

resource "aws_route53_zone" "private" {
  name             = local.private_zone
  vpc {
    vpc_id         = aws_vpc.default.id
  }
  tags = {
    Name           = "${terraform.workspace}-private"
    Environment    = terraform.workspace
  }
}

## --------- Security groups ---------------------------------------------------

resource "aws_security_group" "public" {
  for_each         = local.vars.security_groups["public"]
  name             = "${terraform.workspace}-${each.key}-public"
  description      = each.value.description
  vpc_id           = aws_vpc.default.id
  dynamic "ingress" {
    for_each       = each.value.ports
    content {
      from_port    = ingress.value
      to_port      = ingress.value
      protocol     = "tcp"
      cidr_blocks  = [local.all_ipv4]
    }
  }
  egress {
    description    = "All IPv4"
    from_port      = 0
    to_port        = 0
    protocol       = "-1"
    cidr_blocks    = [local.all_ipv4]
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
  vpc_id           = aws_vpc.default.id
  dynamic "ingress" {
    for_each       = each.value.ports
    content {
      from_port    = ingress.value
      to_port      = ingress.value
      protocol     = "tcp"
      cidr_blocks  = values(aws_subnet.subnets)[*].cidr_block
    }
  }
  egress {
    description    = "Any subnet"
    from_port      = 0
    to_port        = 0
    protocol       = "-1"
    cidr_blocks    = values(aws_subnet.subnets)[*].cidr_block
  }
  tags = {
    Name           = "${terraform.workspace}-${each.key}-private"
    Environment    = terraform.workspace
  }
}

## --------- Roles and policies (shared across workspaces) ---------------------

resource "aws_iam_role" "AlpineContainer" {
  name                  = "AlpineContainer"
  description           = "Allows EC2 instances to run the ECS Agent and CloudWatch Logs Agent."
  assume_role_policy    = file("etc/policies/EC2AssumeRole.json")
  force_detach_policies = true
  max_session_duration  = 3600
}

resource "aws_iam_instance_profile" "AlpineContainer" {
  name                  = "AlpineContainer"
  role                  = "AlpineContainer"
}

resource "aws_iam_policy" "ECSContainerInstance" {
  name                  = "ECSContainerInstance"
  description           = "Allows EC2 instances to create CloudWatch log groups, push logs, and stop ECS tasks."
  policy                = file("etc/policies/ECSContainerInstance.json")
}

resource "aws_iam_role_policy_attachment" "ECSContainerInstance" {
  role                  = aws_iam_role.AlpineContainer.name
  policy_arn            = aws_iam_policy.ECSContainerInstance.arn
}

resource "aws_iam_role_policy_attachment" "AmazonEC2ContainerServiceforEC2Role" {
  role                  = aws_iam_role.AlpineContainer.name
  policy_arn            = data.aws_iam_policy.AmazonEC2ContainerServiceforEC2Role.arn
}

## --------- Roles and policies (environment-specific) -------------------------

resource "aws_iam_role" "ecsTaskExecutionRole" {
  name_prefix           = "${terraform.workspace}-"
  description           = "Environment ${terraform.workspace}: ECS task execution."
  assume_role_policy    = file("etc/policies/ECSAssumeRole.json")
  force_detach_policies = true
  max_session_duration  = 3600
  tags = {
    Environment         = terraform.workspace
  }
}

resource "aws_iam_policy" "ecsTaskExecutionPolicy" {
  name_prefix           = "${terraform.workspace}-"
  description           = "Environment ${terraform.workspace}: local ECS task execution permissions."
  policy                = templatefile("etc/policies/ECSTaskExecution.json", { secrets = aws_ssm_parameter.secrets })
}

resource "aws_iam_role_policy_attachment" "ecsTaskExecutionPolicy" {
  role                  = aws_iam_role.ecsTaskExecutionRole.name
  policy_arn            = aws_iam_policy.ecsTaskExecutionPolicy.arn
}

resource "aws_iam_role_policy_attachment" "AmazonECSTaskExecutionRolePolicy" {
  role                  = aws_iam_role.ecsTaskExecutionRole.name
  policy_arn            = data.aws_iam_policy.AmazonECSTaskExecutionRolePolicy.arn
}

## --------- Keys and secrets --------------------------------------------------

resource "aws_key_pair" "production" {
  key_name         = local.vars.ec2_ssh_key_name
  public_key       = file("${local.vars.ec2_ssh_key}")
}

# Generate n random passwords for each item in the 'secrets' map.
resource "random_password" "passwords" {
  count            = length(local.vars.secrets)
  length           = local.vars.secrets_length
  special          = false
}

# Slightly convoluted: create SSM encrypted parameters for n secrets
resource "aws_ssm_parameter" "secrets" {
  for_each         = toset(keys(local.vars.secrets))
  name             = "/${terraform.workspace}/${each.value}"
  description      = "${local.vars.secrets[each.value].description}"
  type             = "SecureString"
  value            = random_password.passwords[index(keys(local.vars.secrets), each.value)].result
  overwrite        = true
  tags = {
    Environment    = terraform.workspace
  }
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
  for_each = aws_subnet.subnets
  file_system_id   = aws_efs_file_system.nfs.id
  subnet_id        = each.value.id
  security_groups  = [aws_security_group.private["nfs"].id]
}

## --------- ECS cluster -------------------------------------------------------

resource "aws_ecs_cluster" "hello" {
  name = "${terraform.workspace}"
  tags = {
    Name         = "ecs"
    Environment  = terraform.workspace
  }
}

resource "aws_ecs_task_definition" "hello" {
  family                     = "nginx-hello"
  container_definitions      = jsonencode(
    [
      {
        cpu                  = 0
        environment          = []
        essential            = true
        hostname             = "nginx-hello.private"
        image                = "nginxdemos/hello"
        memoryReservation    = 256
        mountPoints          = []
        name                 = "nginx-hello"
        portMappings         = [
          {
            hostPort         = 80
            containerPort    = 80
            protocol         = "tcp"
          },
        ]
        volumesFrom          = []
      },
    ]
  )
  execution_role_arn         = aws_iam_role.ecsTaskExecutionRole.arn
  network_mode               = "host"
  memory                     = "256"
  requires_compatibilities   = [ "EC2" ]
  placement_constraints {
    type           = "memberOf"
    expression     = "attribute:Role == 'www'"
  }
  tags = {
    Name                     = "nginx-hello-task"
    Environment              = terraform.workspace
  }
}

resource "aws_ecs_service" "hello" {
  name             = "hello"
  cluster          = aws_ecs_cluster.hello.arn
  task_definition  = aws_ecs_task_definition.hello.arn
  launch_type      = "EC2"
  scheduling_strategy = "REPLICA"
  desired_count    = 1
  ordered_placement_strategy {
    type           = "binpack"
    field          = "memory"
  }
  lifecycle {
    ignore_changes = ["desired_count"]
  }
  tags = {
    Name           = "nginx-hello-service"
    Environment    = terraform.workspace
  }
}

## --------- Instances ---------------------------------------------------------

resource "aws_instance" "www" {
  depends_on       = [aws_efs_mount_target.nfs, aws_route.internet]
  key_name         = local.vars.ec2_ssh_key_name
  ami              = local.vars.ec2_instance_ami
  instance_type    = local.vars.ec2_instance_type
  iam_instance_profile = aws_iam_instance_profile.AlpineContainer.name
  vpc_security_group_ids = [aws_security_group.public["ssh"].id,
                      aws_security_group.public["https"].id,
                      aws_security_group.private["mailman-web"].id]
  monitoring       = true
  subnet_id        = aws_subnet.subnets["subnet1"].id
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

resource "aws_route53_record" "www" {
  zone_id          = aws_route53_zone.private.zone_id
  name             = "www.${local.private_zone}"
  type             = "A"
  ttl              = "300"
  records          = [aws_instance.www.private_ip]
  allow_overwrite  = true
}

resource "aws_instance" "mail" {
  depends_on       = [aws_instance.www]
  key_name         = local.vars.ec2_ssh_key_name
  ami              = local.vars.ec2_instance_ami
  instance_type    = local.vars.ec2_instance_type
  iam_instance_profile = aws_iam_instance_profile.AlpineContainer.name
  vpc_security_group_ids = [aws_security_group.public["ssh"].id,
                      aws_security_group.public["smtp"].id,
                      aws_security_group.private["postgres"].id,
                      aws_security_group.private["mailman-core"].id]
  monitoring       = true
  subnet_id        = aws_subnet.subnets["subnet2"].id
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
  provisioner "local-exec" {
    command        = <<-EOT
        wait 30; \
        ansible-playbook \
            --ssh-extra-args='-o StrictHostKeyChecking=no' \
            ${local.vars.ansible_playbook}
        EOT
  }
}

resource "aws_route53_record" "mail" {
  zone_id          = aws_route53_zone.private.zone_id
  name             = "mail.${local.private_zone}"
  type             = "A"
  ttl              = "300"
  records          = [aws_instance.mail.private_ip]
  allow_overwrite  = true
}
