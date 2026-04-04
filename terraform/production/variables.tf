variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
}

variable "microservices" {
  description = "Lista dos nomes dos microsserviços para criação dos ECRs"
  type        = list(string)
}

variable "db_password_auth" {
  type        = string
  sensitive   = true
  description = "Password for the Auth DB"
}

variable "db_password_flag" {
  type        = string
  sensitive   = true
  description = "Password for the Flag DB"
}

variable "db_password_targeting" {
  type        = string
  sensitive   = true
  description = "Password for the Targeting DB"
}
