# ========== INPUT VARIABLES ===================================================

variable "root" {
  type = any
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = map(string)
}

variable "efs_id" {
  type = string
}

variable "instance_profile" {
  type = string
}


# ========== RESOURCES =========================================================

## --------- EC2 instances -----------------------------------------------------

resource "aws_instance" "www" {
  key_name         = var.root.ec2_ssh_key_name
  ami              = var.root.ec2_instance_ami
  instance_type    = var.root.ec2_instance_type
  iam_instance_profile       = var.instance_profile
  vpc_security_group_ids     = [aws_security_group.ssh.id]
  monitoring       = true
  subnet_id        = var.subnet_ids["subnet1"]
  associate_public_ip_address = true
  tags = {
    Name           = "${var.root.ec2_env}-www"
    Environment    = var.root.ec2_env
    Node           = "www"
    EfsVolume      = var.efs_id
  }
  volume_tags = {
    Name           = "${var.root.ec2_env}-www"
    Environment    = var.root.ec2_env
    Node           = "www"
  }
  user_data        = file("${path.module}/ec2_init.sh")
}

resource "aws_instance" "mail" {
  key_name         = var.root.ec2_ssh_key_name
  ami              = var.root.ec2_instance_ami
  instance_type    = var.root.ec2_instance_type
  iam_instance_profile       = var.instance_profile
  vpc_security_group_ids     = [aws_security_group.ssh.id]
  monitoring       = true
  subnet_id        = var.subnet_ids["subnet2"]
  associate_public_ip_address = true
  tags = {
    Name           = "${var.root.ec2_env}-mail"
    Environment    = var.root.ec2_env
    Node           = "mail"
    EfsVolume      = var.efs_id
  }
  volume_tags = {
    Name           = "${var.root.ec2_env}-mail"
    Environment    = var.root.ec2_env
    Node           = "mail"
  }
  user_data        = file("${path.module}/ec2_init.sh")
}

## --------- Ansible provisioner -----------------------------------------------

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
            ${var.root.ansible_playbook}
        EOT
  }
}

## --------- SSH security group ------------------------------------------------

resource "aws_security_group" "ssh" {
  name             = "${var.root.ec2_env}-ssh-public"
  description      = "SSH"
  vpc_id           = var.vpc_id
  ingress {
    from_port      = 22
    to_port        = 22
    protocol       = "tcp"
    cidr_blocks    = ["0.0.0.0/0"]
  }
  egress {
    description    = "All IPv4"
    from_port      = 0
    to_port        = 0
    protocol       = "-1"
    cidr_blocks    = ["0.0.0.0/0"]
  }
  tags = {
    Name           = "${var.root.ec2_env}-ssh-public"
    Environment    = var.root.ec2_env
  }
}


# ========== OUTPUT VARIABLES ==================================================

output "private_ips" {
  description      = "Map with keys = node names, and values = private IP addresses."
  value            = { "www": aws_instance.www.private_ip,
                       "mail": aws_instance.mail.private_ip }
}

output "public_ips" {
  description      = "Map with keys = node names, and values = public IP addresses."
  value            = { "www": aws_instance.www.public_ip,
                       "mail": aws_instance.mail.public_ip }
}
