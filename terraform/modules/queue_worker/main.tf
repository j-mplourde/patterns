# queue_worker: wires a Lambda function as a consumer of an SQS queue. The
# queue itself is created externally (this module intentionally takes only the
# queue ARN as input so a single queue can power N workers).

variable "function_arn" { type = string }
variable "function_name" { type = string }
variable "queue_arn" { type = string }
variable "batch_size" {
  type    = number
  default = 10
}
variable "maximum_concurrency" {
  type    = number
  default = 10
}

resource "aws_lambda_event_source_mapping" "this" {
  event_source_arn = var.queue_arn
  function_name    = var.function_arn
  batch_size       = var.batch_size

  scaling_config { maximum_concurrency = var.maximum_concurrency }
}

# Grant the function permission to consume the queue.
data "aws_iam_policy_document" "consume" {
  statement {
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
    ]
    resources = [var.queue_arn]
  }
}

resource "aws_iam_policy" "consume" {
  name   = "${var.function_name}-queue-consume"
  policy = data.aws_iam_policy_document.consume.json
}

output "event_source_mapping_arn" { value = aws_lambda_event_source_mapping.this.arn }
output "consume_policy_arn" { value = aws_iam_policy.consume.arn }
