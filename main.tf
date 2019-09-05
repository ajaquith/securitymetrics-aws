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
  provisioner "local-exec" {
    command        = <<-EOT
        wait 30; \
        ansible-playbook \
            -vvv \
            -i ${local.vars.ansible_inventory} \
            --user ${local.vars.ansible_user} \
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
