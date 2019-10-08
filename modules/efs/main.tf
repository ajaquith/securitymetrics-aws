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

variable "subnet_blocks" {
  type = map(string)
}


# ========== RESOURCES =========================================================

resource "aws_efs_file_system" "efs" {
  creation_token   = "nfs"
  tags = {
    Name           = "${var.root.ec2_env}-efs"
    Environment    = var.root.ec2_env
  }
}

resource "aws_efs_mount_target" "efs" {
  for_each         = var.subnet_ids
  file_system_id   = aws_efs_file_system.efs.id
  subnet_id        = each.value
  security_groups  = [aws_security_group.efs.id]
}

resource "aws_security_group" "efs" {
  name             = "${var.root.ec2_env}-efs-private"
  description      = "NFS"
  vpc_id           = var.vpc_id
  ingress {
    from_port      = 2049
    to_port        = 2049
    protocol       = "tcp"
    cidr_blocks    = values(var.subnet_blocks)
  }
  egress {
    description    = "Any subnet"
    from_port      = 0
    to_port        = 0
    protocol       = "-1"
    cidr_blocks    = values(var.subnet_blocks)
  }
  tags = {
    Name           = "${var.root.ec2_env}-efs-private"
    Environment    = var.root.ec2_env
  }
}


# ========== OUTPUT VARIABLES ==================================================

output "id" {
  description      = "EFS file system ID." 
  value            = aws_efs_file_system.efs.id
}
