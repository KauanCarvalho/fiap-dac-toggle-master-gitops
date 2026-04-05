output "ecr_repository_urls" {
  description = "URLs of the created ECR repositories"
  value       = { for k, v in module.ecr_repositories : k => v.repository_url }
}

output "evaluation_sqs_url" {
  description = "The URL of the evaluation-events SQS queue"
  value       = module.evaluation_sqs.queue_url
}

output "evaluation_sqs_arn" {
  description = "The ARN of the evaluation-events SQS queue"
  value       = module.evaluation_sqs.queue_arn
}

output "vpc_id" {
  description = "VPC ID of the main network"
  value       = module.vpc.vpc_id
}

output "eks_sg_id" {
  description = "Security Group ID where EKS nodes will be attached"
  value       = module.eks_sg.sg_id
}

output "redis_primary_endpoint" {
  description = "Primary endpoint address of the Redis cluster"
  value       = module.redis.redis_primary_endpoint
}

output "redis_connection_string" {
  description = "Connection string pre-formatted for Kubernetes configmaps"
  value       = "redis://${module.redis.redis_primary_endpoint}:6379"
}

output "auth_db_connection_string" {
  description = "Postgres connection string for auth-service-db"
  value       = "postgres://postgres:${var.db_password_auth}@${module.rds_auth.endpoint}/auth_db?sslmode=require"
  sensitive   = true
}

output "flag_db_connection_string" {
  description = "Postgres connection string for flag-service-db"
  value       = "postgres://postgres:${var.db_password_flag}@${module.rds_flag.endpoint}/flag_db?sslmode=require"
  sensitive   = true
}

output "targeting_db_connection_string" {
  description = "Postgres connection string for targeting-service-db"
  value       = "postgres://postgres:${var.db_password_targeting}@${module.rds_targeting.endpoint}/targeting_db?sslmode=require"
  sensitive   = true
}

output "eks_cluster_endpoint" {
  description = "EKS Cluster API Endpoint"
  value       = module.eks.cluster_endpoint
}

output "ingress_load_balancer_hostname" {
  value       = data.kubernetes_service.ingress_nginx.status[0].load_balancer[0].ingress[0].hostname
  description = "The DNS name of the Ingress Load Balancer"
}
