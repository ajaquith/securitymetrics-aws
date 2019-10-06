# ========== OUTPUT VARIABLES ==================================================

output "secrets" {
  description      = "ARNs for secrets" 
  value            = module.secrets.secrets
}

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
  value            = aws_efs_file_system.nfs.id
}

output "ec2_environment" {
  description      = "EC2 environment, aka terraform workspace"
  value            = terraform.workspace
}
