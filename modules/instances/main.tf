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

resource "aws_instance" "nodes" {
  for_each         = var.root.instances
  key_name         = var.root.ec2_ssh_key_name
  ami              = var.root.ec2_instance_ami
  instance_type    = var.root.ec2_instance_type
  iam_instance_profile       = var.instance_profile
  vpc_security_group_ids     = [aws_security_group.ssh.id]
  monitoring       = true
  subnet_id        = var.subnet_ids[each.value]
  associate_public_ip_address = true
  tags = {
    Name           = "${var.root.ec2_env}-${each.key}"
    Environment    = var.root.ec2_env
    Node           = each.key
    EfsVolume      = var.efs_id
  }
  volume_tags = {
    Name           = "${var.root.ec2_env}-${each.key}"
    Environment    = var.root.ec2_env
    Node           = each.key
  }
  user_data        = file("${path.module}/ec2_init.sh")
}

## --------- Ansible provisioner -----------------------------------------------

resource "null_resource" "instances" {
  # Changes to any instance of the cluster requires re-provisioning
  triggers = {
    instance_ids = "${join(",", [for node in aws_instance.nodes: node.id]) }"
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
  value            = { for i in aws_instance.nodes: i.tags["Node"] => i.private_ip }
}

output "public_ips" {
  description      = "Map with keys = node names, and values = public IP addresses."
  value            = { for i in aws_instance.nodes: i.tags["Node"] => i.public_ip }
}
