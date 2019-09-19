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

data "aws_route53_zone" "public" {
  name = "${local.vars.public_domain}."
  private_zone = false
}
data "aws_iam_role" "ecsTaskExecutionRole" { name = "ecsTaskExecutionRole"}


# ========== RESOURCES =========================================================

## --------- Keys---------------------------------------------------------------

resource "aws_key_pair" "production" {
  key_name         = local.vars.ec2_ssh_key_name
  public_key       = file("${local.vars.ec2_ssh_key}")
}

## --------- Virtual Private Cloud (VPC) ---------------------------------------

resource "aws_internet_gateway" "default" {
  vpc_id           = aws_vpc.default.id
  tags = {
    Name           = "igw"
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
    Name           = "vpc"
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
  execution_role_arn         = data.aws_iam_role.ecsTaskExecutionRole.arn
  network_mode               = "host"
  memory                     = "256"
  requires_compatibilities   = [ "EC2" ]
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
  desired_count = 1
  ordered_placement_strategy {
    type  = "binpack"
    field = "cpu"
  }
  lifecycle {
    ignore_changes = ["desired_count"]
  }
  tags = {
    Name                     = "nginx-hello-service"
    Environment              = terraform.workspace
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
  iam_instance_profile = local.vars.ec2_iam_role
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
  iam_instance_profile = local.vars.ec2_iam_role
  vpc_security_group_ids = [aws_security_group.ssh.id,
                      aws_security_group.smtp.id,
                      aws_security_group.https.id]
  monitoring       = true
  subnet_id        = aws_subnet.az1.id
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
