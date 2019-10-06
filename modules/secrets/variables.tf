# ========== INPUT VARIABLES ===================================================

variable "secrets" {
  type = map
}

variable "secrets_length" {
  type = number
}

variable "postgres_user" {
  type = string
}

variable "postgres_db" {
  type = string
}

variable "private_zone" {
  type = string
}
