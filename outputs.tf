# ========== OUTPUT VARIABLES ==================================================

output "www_host" {
  description      = "Web server name" 
  value            = aws_instance.www.public_dns
}

output "mail_host" {
  description      = "Web server name" 
  value            = aws_instance.mail.public_dns
}

output "ec2_instance_id" {
  description      = "Instance ID"
  value            = aws_instance.www.id
}

output "efs_id" {
  description      = "Elastic File Service ID"
  value            = aws_efs_file_system.nfs.id
}

output "ec2_environment" {
  description      = "EC2 environment, aka terraform workspace"
  value            = terraform.workspace
}
