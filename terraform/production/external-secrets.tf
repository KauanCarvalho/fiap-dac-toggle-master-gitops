resource "aws_secretsmanager_secret" "db_auth" {
  name = "togglemaster/auth/db_url"
}

resource "aws_secretsmanager_secret_version" "db_auth" {
  secret_id     = aws_secretsmanager_secret.db_auth.id
  secret_string = "postgres://postgres:${var.db_password_auth}@${module.rds_auth.endpoint}/${module.rds_auth.db_name}"
}

resource "aws_secretsmanager_secret" "auth_master_key" {
  name = "togglemaster/auth/master_key"
}

resource "aws_secretsmanager_secret_version" "auth_master_key" {
  secret_id     = aws_secretsmanager_secret.auth_master_key.id
  secret_string = var.auth_master_key
}

resource "aws_secretsmanager_secret" "db_flag" {
  name = "togglemaster/flag/db_url"
}

resource "aws_secretsmanager_secret_version" "db_flag" {
  secret_id     = aws_secretsmanager_secret.db_flag.id
  secret_string = "postgres://postgres:${var.db_password_flag}@${module.rds_flag.endpoint}/${module.rds_flag.db_name}"
}

resource "aws_secretsmanager_secret" "db_targeting" {
  name = "togglemaster/targeting/db_url"
}

resource "aws_secretsmanager_secret_version" "db_targeting" {
  secret_id     = aws_secretsmanager_secret.db_targeting.id
  secret_string = "postgres://postgres:${var.db_password_targeting}@${module.rds_targeting.endpoint}/${module.rds_targeting.db_name}"
}

resource "aws_secretsmanager_secret" "aws_access_key" { name = "togglemaster/analytics/access_key" }
resource "aws_secretsmanager_secret_version" "aws_access_key" {
  secret_id     = aws_secretsmanager_secret.aws_access_key.id
  secret_string = var.aws_access_key
}

resource "aws_secretsmanager_secret" "aws_secret_key" { name = "togglemaster/analytics/secret_key" }
resource "aws_secretsmanager_secret_version" "aws_secret_key" {
  secret_id     = aws_secretsmanager_secret.aws_secret_key.id
  secret_string = var.aws_secret_key
}

resource "aws_secretsmanager_secret" "aws_session_token" { name = "togglemaster/analytics/session_token" }
resource "aws_secretsmanager_secret_version" "aws_session_token" {
  secret_id     = aws_secretsmanager_secret.aws_session_token.id
  secret_string = var.aws_session_token
}

resource "aws_secretsmanager_secret" "eval_api_key" { name = "togglemaster/evaluation/api_key" }
resource "aws_secretsmanager_secret_version" "eval_api_key" {
  secret_id     = aws_secretsmanager_secret.eval_api_key.id
  secret_string = var.eval_api_key
}

resource "aws_secretsmanager_secret" "eval_access_key" { name = "togglemaster/evaluation/access_key" }
resource "aws_secretsmanager_secret_version" "eval_access_key" {
  secret_id     = aws_secretsmanager_secret.eval_access_key.id
  secret_string = var.aws_access_key
}

resource "aws_secretsmanager_secret" "eval_secret_key" { name = "togglemaster/evaluation/secret_key" }
resource "aws_secretsmanager_secret_version" "eval_secret_key" {
  secret_id     = aws_secretsmanager_secret.eval_secret_key.id
  secret_string = var.aws_secret_key
}

resource "aws_secretsmanager_secret" "eval_session_token" { name = "togglemaster/evaluation/session_token" }
resource "aws_secretsmanager_secret_version" "eval_session_token" {
  secret_id     = aws_secretsmanager_secret.eval_session_token.id
  secret_string = var.aws_session_token
}

resource "aws_secretsmanager_secret" "eval_redis_url" {
  name = "togglemaster/evaluation/redis_url"
}

resource "aws_secretsmanager_secret_version" "eval_redis_url" {
  secret_id     = aws_secretsmanager_secret.eval_redis_url.id
  secret_string = "redis://${module.redis.redis_primary_endpoint}:6379"
}

resource "aws_secretsmanager_secret" "common_sqs_url" {
  name = "togglemaster/common/sqs_url"
}

resource "aws_secretsmanager_secret_version" "common_sqs_url" {
  secret_id     = aws_secretsmanager_secret.common_sqs_url.id
  secret_string = module.evaluation_sqs.queue_url
}

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }

  depends_on = [module.eks]
}

resource "kubernetes_secret_v1" "aws_creds" {
  metadata {
    name      = "aws-creds"
    namespace = "external-secrets"
  }

  data = {
    access-key    = var.aws_access_key
    secret-key    = var.aws_secret_key
    session-token = var.aws_session_token
  }

  depends_on = [helm_release.external_secrets]
}
