# ----- Self-Healing Bridge: Alertmanager -> GitHub repository_dispatch -----
# Quando um alerta dispara, o Alertmanager chama esta Function URL, que aciona
# via repository_dispatch o workflow self-healing.yml no repositório de
# aplicação (fiap-dac-toggle-master) — sem intervenção humana.

data "archive_file" "self_healing_lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/self-healing/main.py"
  output_path = "${path.module}/lambda/self-healing/main.zip"
}

resource "aws_iam_role" "self_healing_lambda" {
  name = "togglemaster-self-healing-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "self_healing_lambda_logs" {
  role       = aws_iam_role.self_healing_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "self_healing" {
  function_name    = "togglemaster-self-healing-bridge"
  role             = aws_iam_role.self_healing_lambda.arn
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

  depends_on = [aws_iam_role_policy_attachment.self_healing_lambda_logs]
}

resource "aws_lambda_function_url" "self_healing" {
  function_name      = aws_lambda_function.self_healing.function_name
  authorization_type = "NONE"
}

output "self_healing_webhook_url" {
  description = "URL do bridge de self-healing (sem o token — ver var.self_healing_webhook_token)"
  value       = aws_lambda_function_url.self_healing.function_url
}
