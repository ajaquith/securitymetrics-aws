# ========== PROVIDERS =========================================================

provider "aws" { 
  profile = "default"
  region = var.ec2_region
}


# ========== DATA SOURCES (looked up by ID) ====================================

data "aws_vpc" "default"     { id = var.aws_vpc_id }
data "aws_subnet" "default"  { id = var.aws_vpc_subnet_id }
data "aws_route53_zone" "server" {
  name = "${var.server_domain}."
  private_zone = false
}


# ========== RESOURCES =========================================================

## --------- Keys---------------------------------------------------------------

resource "aws_key_pair" "production" {
  key_name         = var.ec2_ssh_key_name
  public_key       = file("${var.ec2_ssh_key}")
}

## --------- NFS shared storage ------------------------------------------------

resource "aws_efs_file_system" "nfs" {
  creation_token   = "${var.ec2_environment}-nfs"
  tags = {
    Name           = "${var.ec2_environment}-nfs"
    Environment    = var.ec2_environment
  }
}

resource "aws_efs_mount_target" "nfs" {
  file_system_id   = aws_efs_file_system.nfs.id
  subnet_id        = data.aws_subnet.default.id
  security_groups  = [aws_security_group.nfs.id]
}

resource "aws_security_group" "nfs" {
  name             = "${var.ec2_environment}-nfs"
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
    Name           = "${var.ec2_environment}-nfs"
    Environment    = var.ec2_environment
  }
}

## --------- Server ------------------------------------------------------------

resource "aws_eip" "server" {
  instance         = aws_instance.server.id
  tags = {
    Name           = var.server_name
    Environment    = var.ec2_environment
  }
}

resource "aws_security_group" "ssh" {
  name             = "${var.ec2_environment}-ssh"
  description      = "SSH"
  vpc_id           = data.aws_vpc.default.id
  ingress {
    description    = "SSH"
    from_port      = 22
    to_port        = 22
    protocol       = "tcp"
    cidr_blocks    = [var.all_ipv4]
  }
  egress {
    description    = "All IPv4"
    from_port      = 0
    to_port        = 0
    protocol       = "-1"
    cidr_blocks    = [var.all_ipv4]
  }
  tags = {
    Environment    = var.ec2_environment
  }
}

resource "aws_security_group" "smtp" {
  name             = "${var.ec2_environment}-smtp"
  description      = "SMTP"
  vpc_id           = data.aws_vpc.default.id
  ingress {
    description    = "SMTP"
    from_port      = 25
    to_port        = 25
    protocol       = "tcp"
    cidr_blocks    = [var.all_ipv4]
  }
  egress {
    description    = "All IPv4"
    from_port      = 0
    to_port        = 0
    protocol       = "-1"
    cidr_blocks    = [var.all_ipv4]
  }
  tags = {
    Environment    = var.ec2_environment
  }
}

resource "aws_security_group" "https" {
  name             = "${var.ec2_environment}-https"
  description      = "HTTP/S"
  vpc_id           = data.aws_vpc.default.id
  ingress {
    description    = "HTTP"
    from_port      = 80
    to_port        = 80
    protocol       = "tcp"
    cidr_blocks    = [var.all_ipv4]
  }
  ingress {
    description    = "HTTPS"
    from_port      = 443
    to_port        = 443
    protocol       = "tcp"
    cidr_blocks    = [var.all_ipv4]
  }
  egress {
    description    = "All IPv4"
    from_port      = 0
    to_port        = 0
    protocol       = "-1"
    cidr_blocks    = [var.all_ipv4]
  }
  tags = {
    Environment    = var.ec2_environment
  }
}

resource "aws_instance" "server" {
  depends_on       = [aws_efs_mount_target.nfs]
  key_name         = var.ec2_ssh_key_name
  ami              = var.ec2_instance_ami
  instance_type    = var.ec2_instance_type
  iam_instance_profile = var.ec2_iam_role
  vpc_security_group_ids = [aws_security_group.ssh.id,
                      aws_security_group.smtp.id,
                      aws_security_group.https.id]
  monitoring       = true
  subnet_id        = data.aws_subnet.default.id
  associate_public_ip_address = true
  tags = {
    Name           = var.server_name
    Environment    = var.ec2_environment
  }
  volume_tags = {
    Name           = var.server_name
    Environment    = var.ec2_environment
  }
  provisioner "local-exec" {
    command        = <<-EOT
        wait 30; \
        ansible-playbook \
            -vvv \
            -i ${var.ansible_inventory} \
            --extra-vars 'ec2_environment=${var.ec2_environment}' \
            --user ${var.ansible_user} \
            --private-key ${var.ec2_ssh_key} \
            --ssh-extra-args='-o StrictHostKeyChecking=no' \
            ${var.ansible_playbook}
        EOT
  }
}

resource "aws_route53_record" "server" {
  zone_id          = data.aws_route53_zone.server.zone_id
  name             = var.server_name
  type             = "A"
  ttl              = "300"
  records          = [aws_eip.server.public_ip]
  allow_overwrite  = true
}
