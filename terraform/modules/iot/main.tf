# iot: AWS IoT Core configuration for fleet devices. Provisioning by claim,
# a policy attached to provisioned certs, and a topic rule that publishes
# device telemetry to an SQS queue for downstream processing.

variable "project" { type = string }
variable "environment" { type = string }
variable "telemetry_queue_arn" { type = string }
variable "telemetry_queue_url" { type = string }

resource "aws_iot_policy" "device" {
  name = "${var.project}-${var.environment}-device"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["iot:Connect"], Resource = "*" },
      { Effect = "Allow", Action = ["iot:Publish", "iot:Receive"], Resource = "*" },
      { Effect = "Allow", Action = ["iot:Subscribe"], Resource = "*" },
    ]
  })
}

resource "aws_iam_role" "topic_rule" {
  name = "${var.project}-${var.environment}-iot-rule"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "iot.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "topic_rule" {
  role = aws_iam_role.topic_rule.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:SendMessage"]
      Resource = var.telemetry_queue_arn
    }]
  })
}

resource "aws_iot_topic_rule" "telemetry" {
  name        = "${replace(var.project, "-", "_")}_${var.environment}_telemetry"
  enabled     = true
  sql         = "SELECT * FROM 'devices/+/telemetry'"
  sql_version = "2016-03-23"

  sqs {
    queue_url  = var.telemetry_queue_url
    role_arn   = aws_iam_role.topic_rule.arn
    use_base64 = false
  }
}

output "device_policy_name" { value = aws_iot_policy.device.name }
