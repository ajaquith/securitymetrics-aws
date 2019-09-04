# ========== VARIABLES =========================================================

## --------- Defaults ----------------------------------------------------------

variable "aws_vpc_id"        { default = "vpc-e9fad58d" }            # Existing VPC
variable "aws_vpc_subnet_id" { default = "subnet-d5e34a8d" }         # Existing subnet
variable "ec2_ssh_key_name"  { default = "Andy SSH" }                # Name for uploaded SSH key
variable "ec2_ssh_key"       { default = "~/.ssh/id_rsa.pub" }       # Local path to SSH key
variable "ec2_iam_role"      { default = "AlpineContainer" }         # Role to attach to EC2 instances
variable "ec2_instance_type" { default = "t2.nano" }                 # Size of EC2 instance to provision
variable "all_ipv4"          { default = "0.0.0.0/0" }

## --------- Ansible provisioning ----------------------------------------------

variable "ansible_inventory" { default = "hosts_ec2.yml" }           # Ansible dynamic inventory file 
variable "ansible_playbook"  { default = "playbook_ec2.yml" }        # Ansible playbook for provisioning EC2 instances
variable "ansible_user"      { default = "alpine" }                  # Ansible user for provisioning EC2 instances

## --------- User-defined (in .tfvars files) -----------------------------------

variable "ec2_environment"   { description = "Name of the AWS environment" }
variable "ec2_region"        { description = "Region to deploy AWS environment" }
variable "ec2_instance_ami"  { description = "ID of the AMI used for EC2 instances" }
variable "server_domain"     { description = "Domain of the server, eg securitymetrics.org" }
variable "server_name"       { description = "FQDN of the server eg staging.markerbench.com" }
