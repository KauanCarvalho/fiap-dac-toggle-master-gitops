module "ecr_repositories" {
  source   = "../modules/aws/ecr"
  for_each = toset(var.microservices)

  repository_name = "togglemaster-${each.key}"
}

module "analytics_dynamodb" {
  source              = "../modules/aws/dynamodb"
  dynamodb_table_name = "analytics-events"
  hash_key_name       = "event_id"
}

module "evaluation_sqs" {
  source                     = "../modules/aws/sqs"
  queue_name                 = "evaluation-events"
  receive_wait_time_seconds  = 20
  visibility_timeout_seconds = 60
}

module "vpc" {
  source   = "../modules/aws/vpc"
  vpc_name = "togglemaster-vpc"
  vpc_cidr = "10.0.0.0/16"
}

module "eks_sg" {
  source      = "../modules/aws/sg"
  sg_name     = "togglemaster-eks-sg"
  description = "Security group for EKS nodes"
  vpc_id      = module.vpc.vpc_id
}

module "redis_sg" {
  source      = "../modules/aws/sg"
  sg_name     = "togglemaster-redis-sg"
  description = "Security group for Redis Cluster"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_security_group_rule" "redis_inbound_from_vpc" {
  type              = "ingress"
  from_port         = 6379
  to_port           = 6379
  protocol          = "tcp"
  security_group_id = module.redis_sg.sg_id
  cidr_blocks       = ["10.0.0.0/16"]
  description       = "Allow traffic from VPC (EKS nodes)"
}

module "redis" {
  source             = "../modules/aws/elasticache"
  cluster_id         = "evaluation-service-redis"
  description        = "Redis for evaluation-service"
  subnet_ids         = module.vpc.private_subnets
  security_group_ids = [module.redis_sg.sg_id]
}

resource "aws_db_subnet_group" "rds" {
  name       = "togglemaster-rds-subnets"
  subnet_ids = module.vpc.private_subnets
}

module "rds_sg" {
  source      = "../modules/aws/sg"
  sg_name     = "togglemaster-rds-sg"
  description = "Security group for PostgreSQL RDS instances"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_security_group_rule" "rds_inbound_from_vpc" {
  type              = "ingress"
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  security_group_id = module.rds_sg.sg_id
  cidr_blocks       = ["10.0.0.0/16"]
  description       = "Allow traffic to RDS from VPC (EKS nodes)"
}

module "rds_auth" {
  source             = "../modules/aws/rds"
  db_identifier      = "auth-service-db"
  db_name            = "auth_db"
  password           = var.db_password_auth
  subnet_group_name  = aws_db_subnet_group.rds.name
  security_group_ids = [module.rds_sg.sg_id]
}

module "rds_flag" {
  source             = "../modules/aws/rds"
  db_identifier      = "flag-service-db"
  db_name            = "flag_db"
  password           = var.db_password_flag
  subnet_group_name  = aws_db_subnet_group.rds.name
  security_group_ids = [module.rds_sg.sg_id]
}

module "rds_targeting" {
  source             = "../modules/aws/rds"
  db_identifier      = "targeting-service-db"
  db_name            = "targeting_db"
  password           = var.db_password_targeting
  subnet_group_name  = aws_db_subnet_group.rds.name
  security_group_ids = [module.rds_sg.sg_id]
}

data "aws_iam_role" "lab_role" {
  name = "LabRole"
}

module "eks" {
  source         = "../modules/aws/eks"
  cluster_name   = "togglemaster-cluster"
  role_arn       = data.aws_iam_role.lab_role.arn
  subnet_ids     = module.vpc.public_subnets
  eks_sg_id      = module.eks_sg.sg_id
  instance_types = ["t3.medium"]
  desired_size   = 2
  max_size       = 3
  min_size       = 1
}
