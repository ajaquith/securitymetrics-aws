# ========== INPUT VARIABLES ===================================================

variable "root" {
  type = any
}

variable "secrets" {
  type = map(string)
}

variable "execution_role" {
  type = string
}

# ========== RESOURCES =========================================================

## --------- ECS cluster -------------------------------------------------------

resource "aws_ecs_cluster" "ecs" {
  name = "${var.root.ec2_env}"
  tags = {
    Name         = "ecs"
    Environment  = var.root.ec2_env
  }
}

resource "aws_ecs_task_definition" "postgres" {
  family                     = "postgres"
  container_definitions      = templatefile("${path.module}/postgres.json",
                                            merge(var.root,
                                                  { secrets: var.secrets,
                                                    service: var.root.services["postgres"]}))
  execution_role_arn         = var.execution_role
  network_mode               = "host"
  memory                     = "${var.root.services["postgres"].memory}"
  dynamic "volume" {
    for_each = var.root.services["postgres"].mounts
    content {
      name                   = "${split(":", volume.value)[0]}"
      host_path              = "${var.root[split(":", volume.value)[0]]}"
    }
  }
  requires_compatibilities   = [ "EC2" ]
  tags = {
    Name                     = "${var.root.ec2_env}-postgres"
    Environment              = var.root.ec2_env
  }
}

resource "aws_ecs_task_definition" "mailman-core" {
  family                     = "mailman-core"
  container_definitions      = templatefile("${path.module}/mailman-core.json",
                                            merge(var.root,
                                                  { secrets: var.secrets,
                                                    service: var.root.services["mailman-core"]}))
  execution_role_arn         = var.execution_role
  network_mode               = "host"
  memory                     = "${var.root.services["mailman-core"].memory}"
  dynamic "volume" {
    for_each = var.root.services["mailman-core"].mounts
    content {
      name                   = "${split(":", volume.value)[0]}"
      host_path              = "${var.root[split(":", volume.value)[0]]}"
    }
  }
  requires_compatibilities   = [ "EC2" ]
  tags = {
    Name                     = "${var.root.ec2_env}-mailman-core"
    Environment              = var.root.ec2_env
  }
}

resource "aws_ecs_service" "postgres" {
  name                       = "postgres"
  task_definition            = aws_ecs_task_definition.postgres.arn
  launch_type                = "EC2"
  scheduling_strategy        = "REPLICA"
  desired_count              = 1
  cluster                    = aws_ecs_cluster.ecs.arn
  ordered_placement_strategy {
    type                     = "binpack"
    field                    = "memory"
  }
  placement_constraints {
    type                     = "memberOf"
    expression               = "attribute:Role == '${var.root.services["mailman-core"].placement}'"
  }
  lifecycle {
    ignore_changes           = ["desired_count"]
  }
  tags = {
    Name                     = "${var.root.ec2_env}-postgres"
    Environment              = var.root.ec2_env
  }
}


# ========== OUTPUT VARIABLES ==================================================

output "cluster_arn" {
  description      = "ARN of the ECS cluster." 
  value            = aws_ecs_cluster.ecs.arn
}
