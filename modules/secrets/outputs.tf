# ========== OUTPUT VARIABLES ==================================================

output "secrets" {
  description      = "Secrets map with keys = names, and values = ARNs." 
  value            = zipmap(concat(keys(aws_ssm_parameter.secrets),
                                   ["postgres_url"]),
                            concat(values(aws_ssm_parameter.secrets)[*].arn,
                                   [aws_ssm_parameter.postgres_url.arn]))
}
