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

## --------- Roles and policies (shared across workspaces) ---------------------

resource "aws_iam_role" "ecsTaskExecutionRole" {
  name                  = "ecsTaskExecutionRole"
  description           = "Allows ECS tasks to call AWS services on your behalf."
  assume_role_policy    = file("etc/policies/ECSAssumeRole.json")
  force_detach_policies = false
  max_session_duration  = 3600
}

resource "aws_iam_role_policy_attachment" "AmazonECSTaskExecutionRolePolicy" {
  role                  = aws_iam_role.ecsTaskExecutionRole.name
  policy_arn            = data.aws_iam_policy.AmazonECSTaskExecutionRolePolicy.arn
}

resource "aws_iam_role" "AlpineContainer" {
  name                  = "AlpineContainer"
  description           = "Allows EC2 instances to run the ECS Agent and CloudWatch Logs Agent."
  assume_role_policy    = file("etc/policies/EC2AssumeRole.json")
  force_detach_policies = false
  max_session_duration  = 3600
}

resource "aws_iam_instance_profile" "AlpineContainer" {
  name                  = "AlpineContainer"
  role                  = "AlpineContainer"
}

resource "aws_iam_policy" "ECSContainerInstance" {
  name                  = "ECSContainerInstance"
  description           = "Allows EC2 instances to create CloudWatch log groups, push logs, and stop ECS tasks."
  policy                = templatefile("etc/policies/ECSContainerInstance.json", { django = aws_ssm_parameter.django, mailman = aws_ssm_parameter.mailman, hyperkitty = aws_ssm_parameter.hyperkitty, postgres = aws_ssm_parameter.postgres })
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

## --------- Keys and secrets --------------------------------------------------

resource "aws_key_pair" "production" {
  key_name         = local.vars.ec2_ssh_key_name
  public_key       = file("${local.vars.ec2_ssh_key}")
}

variable "passwords" {
  description      = "Random secret passwords and keys for services."
  default = {
    django         = "Django secret key."
    hyperkitty     = "Hyperkitty API key."
    mailman        = "Mailman REST API password."
    postgres       = "PostgresQL password."
  }
}

resource "random_password" "passwords" {
  count            = length(var.passwords)
  length           = 32
  special          = false
}

resource "aws_ssm_parameter" "django" {
  name        = "/${terraform.workspace}/django_secret_key"
  description = "Django secret key"
  type        = "SecureString"
  value       = random_password.passwords[0].result
  tags = {
    Environment    = terraform.workspace
  }
}

resource "aws_ssm_parameter" "hyperkitty" {
  name        = "/${terraform.workspace}/hyperkitty_api_key"
  description = "Hyperkitty secret key"
  type        = "SecureString"
  value       = random_password.passwords[1].result
  tags = {
    Environment    = terraform.workspace
  }
}

resource "aws_ssm_parameter" "mailman" {
  name        = "/${terraform.workspace}/mailman_rest_password"
  description = "Mailman REST interface password"
  type        = "SecureString"
  value       = random_password.passwords[2].result
  tags = {
    Environment    = terraform.workspace
  }
}

resource "aws_ssm_parameter" "postgres" {
  name        = "/${terraform.workspace}/postgres_password"
  description = "PostgresQL database password"
  type        = "SecureString"
  value       = random_password.passwords[3].result
  tags = {
    Environment    = terraform.workspace
  }
}

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

resource "aws_subnet" "az1" {
  availability_zone                    = local.vars.ec2_subnet_1_az
  cidr_block                           = local.vars.ec2_subnet_1_cidr
  map_public_ip_on_launch              = true
  assign_ipv6_address_on_creation      = false
  vpc_id                               = aws_vpc.default.id
  tags = {
    Name                               = local.vars.ec2_subnet_1_az
    Environment                        = terraform.workspace
  }
}

resource "aws_subnet" "az2" {
  availability_zone                    = local.vars.ec2_subnet_2_az
  cidr_block                           = local.vars.ec2_subnet_2_cidr
  map_public_ip_on_launch              = true
  assign_ipv6_address_on_creation      = false
  vpc_id                               = aws_vpc.default.id
  tags = {
    Name                               = local.vars.ec2_subnet_2_az
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
    Name           = "zone"
    Environment    = terraform.workspace
  }
}

## --------- NFS shared storage ------------------------------------------------

resource "aws_efs_file_system" "nfs" {
  creation_token   = "nfs"
  tags = {
    Name           = "nfs"
    Environment    = terraform.workspace
  }
}

resource "aws_efs_mount_target" "az1" {
  file_system_id   = aws_efs_file_system.nfs.id
  subnet_id        = aws_subnet.az1.id
  security_groups  = [aws_security_group.nfs.id]
}

resource "aws_efs_mount_target" "az2" {
  file_system_id   = aws_efs_file_system.nfs.id
  subnet_id        = aws_subnet.az2.id
  security_groups  = [aws_security_group.nfs.id]
}

resource "aws_security_group" "nfs" {
  name             = "nfs"
  description      = "NFS"
  vpc_id           = aws_vpc.default.id
  ingress {
    description    = "NFS subnet"
    from_port      = 2049
    to_port        = 2049
    protocol       = "tcp"
    cidr_blocks    = [aws_subnet.az1.cidr_block, aws_subnet.az2.cidr_block]
  }
  egress {
    description    = "Any subnet"
    from_port      = 0
    to_port        = 0
    protocol       = "-1"
    cidr_blocks    = [aws_subnet.az1.cidr_block, aws_subnet.az2.cidr_block]
  }
  tags = {
    Name           = "nfs"
    Environment    = terraform.workspace
  }
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

## --------- Server security groups --------------------------------------------

resource "aws_security_group" "ssh" {
  name             = "ssh"
  description      = "SSH"
  vpc_id           = aws_vpc.default.id
  ingress {
    description    = "SSH"
    from_port      = 22
    to_port        = 22
    protocol       = "tcp"
    cidr_blocks    = [local.all_ipv4]
  }
  egress {
    description    = "All IPv4"
    from_port      = 0
    to_port        = 0
    protocol       = "-1"
    cidr_blocks    = [local.all_ipv4]
  }
  tags = {
    Name           = "ssh"
    Environment    = terraform.workspace
  }
}

resource "aws_security_group" "smtp" {
  name             = "smtp"
  description      = "SMTP"
  vpc_id           = aws_vpc.default.id
  ingress {
    description    = "SMTP"
    from_port      = 25
    to_port        = 25
    protocol       = "tcp"
    cidr_blocks    = [local.all_ipv4]
  }
  egress {
    description    = "All IPv4"
    from_port      = 0
    to_port        = 0
    protocol       = "-1"
    cidr_blocks    = [local.all_ipv4]
  }
  tags = {
    Name           = "smtp"
    Environment    = terraform.workspace
  }
}

resource "aws_security_group" "https" {
  name             = "https"
  description      = "HTTP/S"
  vpc_id           = aws_vpc.default.id
  ingress {
    description    = "HTTP"
    from_port      = 80
    to_port        = 80
    protocol       = "tcp"
    cidr_blocks    = [local.all_ipv4]
  }
  ingress {
    description    = "HTTPS"
    from_port      = 443
    to_port        = 443
    protocol       = "tcp"
    cidr_blocks    = [local.all_ipv4]
  }
  egress {
    description    = "All IPv4"
    from_port      = 0
    to_port        = 0
    protocol       = "-1"
    cidr_blocks    = [local.all_ipv4]
  }
  tags = {
    Name           = "https"
    Environment    = terraform.workspace
  }
}

## --------- Servers -----------------------------------------------------------

resource "aws_instance" "www" {
  depends_on       = [aws_efs_mount_target.az1, aws_efs_mount_target.az2, aws_route.internet]
  key_name         = local.vars.ec2_ssh_key_name
  ami              = local.vars.ec2_instance_ami
  instance_type    = local.vars.ec2_instance_type
  iam_instance_profile = aws_iam_instance_profile.AlpineContainer.name
  vpc_security_group_ids = [aws_security_group.ssh.id,
                      aws_security_group.smtp.id,
                      aws_security_group.https.id]
  monitoring       = true
  subnet_id        = aws_subnet.az1.id
  associate_public_ip_address = true
  tags = {
    Name           = "www"
    Environment    = terraform.workspace
    Role           = "www"
    EfsVolume      = aws_efs_file_system.nfs.id
  }
  volume_tags = {
    Name           = "www"
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
  vpc_security_group_ids = [aws_security_group.ssh.id,
                      aws_security_group.smtp.id,
                      aws_security_group.https.id]
  monitoring       = true
  subnet_id        = aws_subnet.az2.id
  associate_public_ip_address = true
  tags = {
    Name           = "mail"
    Environment    = terraform.workspace
    Role           = "mail"
    EfsVolume      = aws_efs_file_system.nfs.id
  }
  volume_tags = {
    Name           = "mail"
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
