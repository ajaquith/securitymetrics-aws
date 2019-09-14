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

data "aws_vpc" "default"     { id = local.vars.aws_vpc_id }
data "aws_subnet" "default"  { id = local.vars.aws_vpc_subnet_id }
data "aws_route53_zone" "server" {
  name = "${local.vars.server_domain}."
  private_zone = false
}
data "aws_iam_role" "ecsTaskExecutionRole" { name = "ecsTaskExecutionRole"}


# ========== RESOURCES =========================================================

## --------- Keys---------------------------------------------------------------

resource "aws_key_pair" "production" {
  key_name         = local.vars.ec2_ssh_key_name
  public_key       = file("${local.vars.ec2_ssh_key}")
}

## --------- NFS shared storage ------------------------------------------------

resource "aws_efs_file_system" "nfs" {
  creation_token   = "${terraform.workspace}-nfs"
  tags = {
    Name           = "${terraform.workspace}-nfs"
    Environment    = terraform.workspace
  }
}

resource "aws_efs_mount_target" "nfs" {
  file_system_id   = aws_efs_file_system.nfs.id
  subnet_id        = data.aws_subnet.default.id
  security_groups  = [aws_security_group.nfs.id]
}

resource "aws_security_group" "nfs" {
  name             = "${terraform.workspace}-nfs"
  description      = "NFS"
  vpc_id           = data.aws_vpc.default.id
  ingress {
    description    = "NFS subnet"
    from_port      = 2049
    to_port        = 2049
    protocol       = "tcp"
    cidr_blocks    = [data.aws_subnet.default.cidr_block]
  }
  egress {
    description    = "Any subnet"
    from_port      = 0
    to_port        = 0
    protocol       = "-1"
    cidr_blocks    = [data.aws_subnet.default.cidr_block]
  }
  tags = {
    Name           = "${terraform.workspace}-nfs"
    Environment    = terraform.workspace
  }
}

## --------- ECS cluster -------------------------------------------------------

resource "aws_ecs_cluster" "hello" {
  name = "${terraform.workspace}"
  tags = {
    Name         = "${terraform.workspace}-ecs"
    Environment  = terraform.workspace
  }
}

resource "aws_ecs_task_definition" "hello" {
  family                     = "nginx-hello-${terraform.workspace}"
  container_definitions      = jsonencode(
    [
      {
        cpu                  = 0
        environment          = []
        essential            = true
        hostname             = "nginx-hello-${terraform.workspace}.private"
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
    Environment    = terraform.workspace
  }
}

resource "aws_ecs_service" "hello" {
  name             = "hello-${terraform.workspace}"
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
}

## --------- Server ------------------------------------------------------------

resource "aws_eip" "server" {
  instance         = aws_instance.server.id
  tags = {
    Name           = local.vars.server_name
    Environment    = terraform.workspace
  }
}

resource "aws_security_group" "ssh" {
  name             = "${terraform.workspace}-ssh"
  description      = "SSH"
  vpc_id           = data.aws_vpc.default.id
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
    Environment    = terraform.workspace
  }
}

resource "aws_security_group" "smtp" {
  name             = "${terraform.workspace}-smtp"
  description      = "SMTP"
  vpc_id           = data.aws_vpc.default.id
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
    Environment    = terraform.workspace
  }
}

resource "aws_security_group" "https" {
  name             = "${terraform.workspace}-https"
  description      = "HTTP/S"
  vpc_id           = data.aws_vpc.default.id
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
    Environment    = terraform.workspace
  }
}

resource "aws_instance" "server" {
  depends_on       = [aws_efs_mount_target.nfs]
  key_name         = local.vars.ec2_ssh_key_name
  ami              = local.vars.ec2_instance_ami
  instance_type    = local.vars.ec2_instance_type
  iam_instance_profile = local.vars.ec2_iam_role
  vpc_security_group_ids = [aws_security_group.ssh.id,
                      aws_security_group.smtp.id,
                      aws_security_group.https.id]
  monitoring       = true
  subnet_id        = data.aws_subnet.default.id
  associate_public_ip_address = true
  tags = {
    Name           = local.vars.server_name
    Environment    = terraform.workspace
  }
  volume_tags = {
    Name           = local.vars.server_name
    Environment    = terraform.workspace
  }
  user_data        = templatefile("roles/base/templates/ec2_init.sh", { cluster = terraform.workspace, nfs_id = aws_efs_file_system.nfs.id })
  provisioner "local-exec" {
    working_dir    = "."
    command        = <<-EOT
        wait 30; \
        ansible-playbook \
            --private-key ${local.vars.ec2_ssh_key} \
            --ssh-extra-args='-o StrictHostKeyChecking=no' \
            ${local.vars.ansible_playbook}
        EOT
  }
}

resource "aws_route53_record" "server" {
  zone_id          = data.aws_route53_zone.server.zone_id
  name             = local.vars.server_name
  type             = "A"
  ttl              = "300"
  records          = [aws_eip.server.public_ip]
  allow_overwrite  = true
}
