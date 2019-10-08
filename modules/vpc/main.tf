# ========== INPUT VARIABLES ===================================================

variable "root" {
  type = any
}


# ========== RESOURCES =========================================================

## --------- Virtual private cloud ---------------------------------------------

resource "aws_vpc" "default" {
  cidr_block                           = var.root.ec2_vpc_cidr
  instance_tenancy                     = "default"
  enable_dns_support                   = true
  enable_dns_hostnames                 = false
  enable_classiclink                   = false
  enable_classiclink_dns_support       = false
  assign_generated_ipv6_cidr_block     = false
  tags = {
    Name           = "${var.root.ec2_env}-vpc"
    Environment    = var.root.ec2_env
  }
}

## --------- Private DNS zone --------------------------------------------------

resource "aws_route53_zone" "private" {
  name             = var.root.private_zone
  vpc {
    vpc_id         = aws_vpc.default.id
  }
  tags = {
    Name           = var.root.private_zone
    Environment    = var.root.ec2_env
  }
}

## --------- Private subnets ---------------------------------------------------

resource "aws_subnet" "subnets" {
  for_each = var.root.subnets
  availability_zone                    = each.value.availability_zone
  cidr_block                           = each.value.cidr_block
  map_public_ip_on_launch              = false
  assign_ipv6_address_on_creation      = false
  vpc_id                               = aws_vpc.default.id
  tags = {
    Name                               = "${var.root.ec2_env}-${each.key}"
    Environment                        = var.root.ec2_env
  }
}

## --------- Internet routes ---------------------------------------------------

resource "aws_internet_gateway" "default" {
  vpc_id           = aws_vpc.default.id
  tags = {
    Name           = "${var.root.ec2_env}-internet"
    Environment    = var.root.ec2_env
  }
}

resource "aws_route" "internet" {
  route_table_id             = aws_vpc.default.default_route_table_id
  destination_cidr_block     = "0.0.0.0/0"
  gateway_id                 = aws_internet_gateway.default.id
}


# ========== OUTPUT VARIABLES ==================================================

output "vpc_id" {
  description      = "ID of the VPC"
  value            = aws_vpc.default.id
}

output "private_zone_id" {
  description      = "Private DNS zone ID"
  value            = aws_route53_zone.private.zone_id
}

output "subnet_ids" {
  description      = "Map with keys = subnet names, and values = subnet IDs."
  value            = zipmap(keys(aws_subnet.subnets),
                            values(aws_subnet.subnets)[*].id)
}

output "subnet_cidr_blocks" {
  description      = "Map with keys = subnet names, and values = subnet CIDRs."
  value            = zipmap(keys(aws_subnet.subnets),
                            values(aws_subnet.subnets)[*].cidr_block)
}

output "any_cidr_block" {
  description      = "All IP addresses"
  value            = "0.0.0.0/0"
}
