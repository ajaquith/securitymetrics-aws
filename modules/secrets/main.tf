# ========== INPUT VARIABLES ===================================================

variable "root" {
  type = any
}

# ========== RESOURCES =========================================================

# Generate n random passwords for each item in the 'secrets' map.
resource "random_password" "passwords" {
  count            = length(var.root.secrets)
  length           = var.root.secrets_length
  special          = false
}

# Slightly convoluted: create SSM encrypted parameters for n secrets
resource "aws_ssm_parameter" "secrets" {
  for_each         = toset(keys(var.root.secrets))
  name             = "/${terraform.workspace}/${each.value}"
  description      = "${var.root.secrets[each.value].description}"
  type             = "SecureString"
  value            = random_password.passwords[index(keys(var.root.secrets), each.value)].result
  overwrite        = true
  tags = {
    Name           = "${terraform.workspace}-${each.value}"
    Environment    = terraform.workspace
  }
}

resource "aws_ssm_parameter" "postgres_url" {
  name             = "/${terraform.workspace}/postgres_url"
  description      = "Mailman database URL"
  type             = "SecureString"
  value            = format("postgres://%s:%s@postgres.%s/%s",
                            var.root.postgres_user,
                            aws_ssm_parameter.secrets["postgres_password"].value,
                            var.root.private_zone,
                            var.root.postgres_db)
  overwrite        = true
  tags = {
    Name           = "${terraform.workspace}-postgres_url"
    Environment    = terraform.workspace
  }
}

# ========== OUTPUT VARIABLES ==================================================

output "secrets" {
  description      = "Secrets map with keys = names, and values = ARNs." 
  value            = zipmap(concat(keys(aws_ssm_parameter.secrets),
                                   ["postgres_url"]),
                            concat(values(aws_ssm_parameter.secrets)[*].arn,
                                   [aws_ssm_parameter.postgres_url.arn]))
}
