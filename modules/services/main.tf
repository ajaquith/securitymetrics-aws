# ========== INPUT VARIABLES ===================================================

variable "root" {
  type = any
}

variable "vpc_id" {
  type = string
}

variable "subnet_blocks" {
  type = map(string)
}

variable "private_ips" {
  type = map(string)
}

variable "execution_role" {
  type = string
}

variable "secrets" {
  type = map(string)
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

## --------- ECS task and service definitions ----------------------------------

resource "aws_ecs_task_definition" "tasks" {
  for_each                   = var.root.services
  family                     = each.key
  container_definitions      = templatefile("${path.module}/${each.key}.json",
                                            merge(var.root,
                                                  { secrets: var.secrets,
                                                    service: each.value}))
  execution_role_arn         = var.execution_role
  network_mode               = "host"
  memory                     = each.value.memory
  dynamic "volume" {
    for_each = each.value.mounts
    content {
      name                   = "${split(":", volume.value)[0]}"
      host_path              = "${var.root[split(":", volume.value)[0]]}"
    }
  }
  requires_compatibilities   = [ "EC2" ]
  tags = {
    Name                     = "${var.root.ec2_env}-${each.key}"
    Environment              = var.root.ec2_env
  }
}

resource "aws_ecs_service" "services" {
  for_each                   = var.root.services
  name                       = each.key
  task_definition            = aws_ecs_task_definition.tasks[each.key].arn
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
    expression               = "attribute:Node == '${var.root.services[each.key].place_on_node}'"
  }
  lifecycle {
    ignore_changes           = ["desired_count"]
  }
  tags = {
    Name                     = "${var.root.ec2_env}-${each.key}"
    Environment              = var.root.ec2_env
    Node                     = var.root.services[each.key].place_on_node
  }
}

## --------- Security groups ---------------------------------------------------

resource "aws_security_group" "tasks" {
  for_each         = var.root.services
  name             = "${var.root.ec2_env}-${each.key}-${each.value.public ? "public" : "private"}"
  description      = each.value.description
  vpc_id           = var.vpc_id
  dynamic "ingress" {
    for_each = each.value.ports
    content {
      from_port    = split(":", ingress.value)[0]
      to_port      = split(":", ingress.value)[0]
      protocol     = "tcp"
      cidr_blocks  = each.value.public ? ["0.0.0.0/0"] : values(var.subnet_blocks)
    }
  }
  egress {
    description    = "${each.value.public ? "All IPv4" : "Any subnet"}"
    from_port      = 0
    to_port        = 0
    protocol       = "-1"
    cidr_blocks    = each.value.public ? ["0.0.0.0/0"] : values(var.subnet_blocks)
  }
  tags = {
    Name           = "${var.root.ec2_env}-${each.key}-${each.value.public ? "public" : "private"}"
    Environment    = var.root.ec2_env
    Node           = each.value.place_on_node
  }
}

## --------- Private DNS registry for services ---------------------------------

resource "aws_route53_zone" "private" {
  name             = var.root.private_zone
  vpc {
    vpc_id         = var.vpc_id
  }
  tags = {
    Name           = var.root.private_zone
    Environment    = var.root.ec2_env
  }
}

resource "aws_route53_record" "private" {
  for_each         = var.root.services
  zone_id          = aws_route53_zone.private.zone_id
  name             = "${each.key}.${var.root.private_zone}"
  type             = "A"
  ttl              = "300"
  records          = [var.private_ips[each.value.place_on_node]]
  allow_overwrite  = true
}


# ========== OUTPUT VARIABLES ==================================================

output "cluster_arn" {
  description      = "ARN of the ECS cluster." 
  value            = aws_ecs_cluster.ecs.arn
}
