#
# Terraform configuration for securitymetrics.org
# Author:  Andrew R Jaquith
# Version: 0.1
#

# ========== VARIABLES =========================================================

## --------- Defaults ----------------------------------------------------------

variable "aws_vpc_id"        { default = "vpc-e9fad58d" }
variable "aws_vpc_subnet_id" { default = "subnet-d5e34a8d" }
variable "ec2_ssh_key_name"  { default = "Andy SSH" }
variable "ec2_ssh_key"       { default = "~/.ssh/id_rsa.pub" }
variable "ec2_instance_type" { default = "t2.nano" }
variable "ec2_iam_role"      { default = "AlpineContainer" }
variable "all_ipv4"          { default = "0.0.0.0/0" }

## --------- User-defined (in .tfvars files) -----------------------------------

variable "ec2_environment"   { description = "Name of the AWS environment" }
variable "ec2_region"        { description = "Region to deploy AWS environment" }
variable "ec2_instance_ami"  { description = "ID of the AMI used for EC2 instances" }
variable "server_domain"     { description = "Domain of the server, eg securitymetrics.org" }
variable "server_name"       { description = "FQDN of the server eg staging.markerbench.com" }


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
    Name           = var.server_name
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
    Name           = var.server_name
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
    Name           = var.server_name
    Environment    = var.ec2_environment
  }
}

resource "aws_instance" "server" {
  depends_on       = [aws_efs_mount_target.nfs]
  key_name         = var.ec2_ssh_key_name
  ami              = var.ec2_instance_ami
  instance_type    = var.ec2_instance_type
  iam_instance_profile = var.ec2_iam_role
  user_data        = file("roles/amazon/files/ec2_init.sh")
  security_groups  = [aws_security_group.ssh.id,
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
}

resource "aws_route53_record" "server" {
  zone_id          = data.aws_route53_zone.server.zone_id
  name             = var.server_name
  type             = "A"
  ttl              = "300"
  records          = [aws_instance.server.public_ip]
  allow_overwrite  = true
}


# ========== OUTPUT VARIABLES ==================================================

output "server_name" {
  description      = "Server name" 
  value            = aws_instance.server.public_dns
}

output "ec2_instance_id" {
  description      = "Instance ID"
  value            = aws_instance.server.id
}

output "ec2_elastic_ip" {
  description      = "Elastic IP"
  value            = aws_instance.server.public_ip
}

output "efs_id" {
  description      = "Elastic File Service ID"
  value            = aws_efs_file_system.nfs.id
}
