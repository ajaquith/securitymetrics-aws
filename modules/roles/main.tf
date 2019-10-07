# ========== INPUT VARIABLES ===================================================

variable "secrets" {
  type = map(string)
}

# ========== DATA SOURCES (looked up by ID) ====================================

data "aws_iam_policy" "AmazonEC2ContainerServiceforEC2Role" {
  arn              = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

data "aws_iam_policy" "AmazonECSTaskExecutionRolePolicy" {
  arn              = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ========== RESOURCES =========================================================

## --------- EC2 instance profile ----------------------------------------------

resource "aws_iam_instance_profile" "EC2Instance" {
  name_prefix           = "${terraform.workspace}-"
  role                  = aws_iam_role.EC2Instance.name
}

resource "aws_iam_role" "EC2Instance" {
  name_prefix           = "${terraform.workspace}-"
  description           = "Environment ${terraform.workspace}: EC2 role for ECS and CloudWatch."
  assume_role_policy    = file("${path.module}/EC2AssumeRole.json")
  force_detach_policies = true
  max_session_duration  = 3600
}

resource "aws_iam_role_policy_attachment" "AmazonEC2ContainerServiceforEC2Role" {
  role                  = aws_iam_role.EC2Instance.name
  policy_arn            = data.aws_iam_policy.AmazonEC2ContainerServiceforEC2Role.arn
}

resource "aws_iam_role_policy_attachment" "ECSContainerInstance" {
  role                  = aws_iam_role.EC2Instance.name
  policy_arn            = aws_iam_policy.ECSContainerInstance.arn
}

## --------- ECS task execution role -------------------------------------------

resource "aws_iam_role" "ecsTaskExecutionRole" {
  name_prefix           = "${terraform.workspace}-"
  description           = "Environment ${terraform.workspace}: ECS task execution."
  assume_role_policy    = file("${path.module}/ECSAssumeRole.json")
  force_detach_policies = true
  max_session_duration  = 3600
  tags = {
    Environment         = terraform.workspace
  }
}

resource "aws_iam_policy" "ECSContainerInstance" {
  name_prefix           = "${terraform.workspace}-"
  description           = "Environment ${terraform.workspace}: EC2 policy for ECS and CloudWatch."
  policy                = file("${path.module}/ECSContainerInstance.json")
}

resource "aws_iam_policy" "ecsTaskExecutionPolicy" {
  name_prefix           = "${terraform.workspace}-"
  description           = "Environment ${terraform.workspace}: ECS task execution permissions."
  policy                = templatefile("${path.module}/ECSTaskExecution.json", { secrets = var.secrets })
}

resource "aws_iam_role_policy_attachment" "ecsTaskExecutionPolicy" {
  role                  = aws_iam_role.ecsTaskExecutionRole.name
  policy_arn            = aws_iam_policy.ecsTaskExecutionPolicy.arn
}

resource "aws_iam_role_policy_attachment" "AmazonECSTaskExecutionRolePolicy" {
  role                  = aws_iam_role.ecsTaskExecutionRole.name
  policy_arn            = data.aws_iam_policy.AmazonECSTaskExecutionRolePolicy.arn
}

# ========== OUTPUT VARIABLES ==================================================

output "execution_role_arn" {
  description      = "ARN of the ECS role used to execute tasks." 
  value            = aws_iam_role.ecsTaskExecutionRole.arn
}

output "iam_instance_profile" {
  description      = "Name of the instance profile used by EC2 nodes." 
  value            = aws_iam_instance_profile.EC2Instance.name
}
