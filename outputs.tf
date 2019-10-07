# ========== OUTPUT VARIABLES ==================================================

output "host_mail" {
  description      = "Mail server name" 
  value            = aws_instance.mail.public_ip
}

output "host_www" {
  description      = "Web server name"
  value            = aws_instance.www.public_ip
}

output "efs_id" {
  description      = "Elastic File Service ID"
  value            = module.efs.id
}

output "ec2_env" {
  description      = "EC2 environment, aka terraform workspace"
  value            = local.root.ec2_env
}
