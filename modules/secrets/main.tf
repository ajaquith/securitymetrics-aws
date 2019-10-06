# ========== RESOURCES =========================================================

# Generate n random passwords for each item in the 'secrets' map.
resource "random_password" "passwords" {
  count            = length(var.secrets)
  length           = var.secrets_length
  special          = false
}

# Slightly convoluted: create SSM encrypted parameters for n secrets
resource "aws_ssm_parameter" "secrets" {
  for_each         = toset(keys(var.secrets))
  name             = "/${terraform.workspace}/${each.value}"
  description      = "${var.secrets[each.value].description}"
  type             = "SecureString"
  value            = random_password.passwords[index(keys(var.secrets), each.value)].result
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
                            var.postgres_user,
                            aws_ssm_parameter.secrets["postgres_password"].value,
                            var.private_zone,
                            var.postgres_db)
  overwrite        = true
  tags = {
    Name           = "${terraform.workspace}-postgres_url"
    Environment    = terraform.workspace
  }
}
