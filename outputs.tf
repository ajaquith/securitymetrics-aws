# ========== OUTPUT VARIABLES ==================================================

output "server_name" {
  description      = "Server name" 
  value            = aws_instance.server.public_dns
}

output "ec2_instance_id" {
  description      = "Instance ID"
  value            = aws_instance.server.id
}

output "ec2_elastic_ip" {
  description      = "Elastic IP"
  value            = aws_eip.server.public_ip
}

output "efs_id" {
  description      = "Elastic File Service ID"
  value            = aws_efs_file_system.nfs.id
}
