# Running Terraform

Displaying the execution plan based on the current environment (Terraform workspace):

        terraform plan
        
Executing the plan for the current environment:

        terraform apply
        
Debugging an operation:

        TF_LOG=DEBUG terraform apply

Creating new environment _tf_ (Terraform workspace)/:

        terraform init
        terraform workspace new tf

Changing to the _tf_ environment:

        terraform workspace select tf

## Remote state persistence
S3 bucket for state storage is:

        cloudadmin.markerbench.com/env/tf/terraform/terraform.tfstate

# Running Ansible

Running the provisioning playbook for the current environment, using the default SSH key and remote user as defined in `ansible.cfg`:

        ansible-playbook playbook.yml
