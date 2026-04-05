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

variable "aws_access_key" {
  description = "AWS Access Key for Lab credentials"
  type        = string
  sensitive   = true
}

variable "aws_secret_key" {
  description = "AWS Secret Key for Lab credentials"
  type        = string
  sensitive   = true
}

variable "aws_session_token" {
  description = "AWS Session Token for Lab credentials"
  type        = string
  sensitive   = true
}

variable "eval_api_key" {
  description = "API Key for Evaluation service"
  type        = string
  sensitive   = true
}

variable "auth_master_key" {
  description = "Master Key for Auth service"
  type        = string
  sensitive   = true
}
