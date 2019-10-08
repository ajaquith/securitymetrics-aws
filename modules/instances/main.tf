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

variable "any_cidr_block" {
  type = string
}

variable "instance_profile" {
  type = string
}


# ========== RESOURCES =========================================================

resource "aws_security_group" "ssh" {
  name             = "${var.root.ec2_env}-ssh-public"
  description      = "SSH"
  vpc_id           = var.vpc_id
  ingress {
    from_port      = 22
    to_port        = 22
    protocol       = "tcp"
    cidr_blocks    = [var.any_cidr_block]
  }
  egress {
    description    = "All IPv4"
    from_port      = 0
    to_port        = 0
    protocol       = "-1"
    cidr_blocks    = [var.any_cidr_block]
  }
  tags = {
    Name           = "${var.root.ec2_env}-ssh-public"
    Environment    = var.root.ec2_env
  }
}


# ========== OUTPUT VARIABLES ==================================================

output "ssh_security_group_id" {
  description      = "IDs of the SSH security group." 
  value            = aws_security_group.ssh.id
}
