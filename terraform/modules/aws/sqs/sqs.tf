resource "aws_sqs_queue" "queue" {
  name                       = var.queue_name
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds

  tags = {
    Name      = var.queue_name
    Project   = "togglemaster"
    ManagedBy = "terraform"
  }
}
