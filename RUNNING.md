# Running Terraform

Displaying the execution plan:

        terraform plan -var-file=tf.tfvars
        
Executing the plan:

        terraform apply -var-file=tf.tfvars

# Running Ansible

        ansible-playbook -i hosts_aws_ec2.yml \
            --extra-vars "ec2_environment='tf'" \
            --user alpine \
            --private-key ~/.ssh/id_rsa \
            playbook_ec2.yml
