# ----- Self-Healing Bridge: Alertmanager -> GitHub repository_dispatch -----
# Quando um alerta dispara, o Alertmanager chama esta Function URL, que aciona
# via repository_dispatch o workflow self-healing.yml no repositório de
# aplicação (fiap-dac-toggle-master) — sem intervenção humana.

data "archive_file" "self_healing_lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/self-healing/main.py"
  output_path = "${path.module}/lambda/self-healing/main.zip"
}

# Contas do AWS Academy (Learner Lab) não permitem iam:CreateRole /
# iam:AttachRolePolicy — reaproveita a mesma "LabRole" já usada pelo
# módulo EKS em main.tf (única role com permissão disponível na conta).
resource "aws_lambda_function" "self_healing" {
  function_name    = "togglemaster-self-healing-bridge"
  role             = data.aws_iam_role.lab_role.arn
  handler          = "main.handler"
  runtime          = "python3.12"
  timeout          = 15
  filename         = data.archive_file.self_healing_lambda.output_path
  source_code_hash = data.archive_file.self_healing_lambda.output_base64sha256

  environment {
    variables = {
      GITHUB_TOKEN  = var.github_dispatch_token
      GITHUB_REPO   = "KauanCarvalho/fiap-dac-toggle-master"
      WEBHOOK_TOKEN = var.self_healing_webhook_token
    }
  }
}

resource "aws_lambda_function_url" "self_healing" {
  function_name      = aws_lambda_function.self_healing.function_name
  authorization_type = "NONE"
}

# authorization_type = "NONE" só desabilita a exigência de assinatura IAM na
# própria Function URL — sem esta permissão de recurso, qualquer chamada
# (inclusive do Alertmanager) recebe 403 Forbidden.
resource "aws_lambda_permission" "self_healing_url_public" {
  statement_id           = "AllowPublicFunctionUrlInvoke"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.self_healing.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

output "self_healing_webhook_url" {
  description = "URL do bridge de self-healing (sem o token — ver var.self_healing_webhook_token)"
  value       = aws_lambda_function_url.self_healing.function_url
}
