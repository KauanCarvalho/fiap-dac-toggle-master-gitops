variable "db_identifier" {
  type        = string
  description = "The name of the RDS instance"
}

variable "db_name" {
  type        = string
  description = "Name of the initial database to create"
}

variable "password" {
  type        = string
  sensitive   = true
  description = "Master password for the postgres user"
}

variable "instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "subnet_group_name" {
  type        = string
  description = "Name of the DB subnet group"
}

variable "security_group_ids" {
  type        = list(string)
  description = "List of VPC Security Group IDs"
}
