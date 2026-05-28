# serverless/main: a single Lambda function with execution role, log group, and
# an optional list of attached managed policies. Pairs with one of the
# `dependency_*` layer modules for runtime dependencies.

variable "function_name" { type = string }
variable "handler" { type = string }
variable "runtime" {
  type    = string
  default = "nodejs22.x"
}
variable "filename" {
  type        = string
  description = "Path to the function's zipped source."
}
variable "layers" {
  type    = list(string)
  default = []
}
variable "environment_variables" {
  type    = map(string)
  default = {}
}
variable "policy_arns" {
  type    = list(string)
  default = []
}
variable "timeout" {
  type    = number
  default = 30
}
variable "memory_size" {
  type    = number
  default = 256
}

resource "aws_iam_role" "this" {
  name = "${var.function_name}-exec"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "basic" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "extra" {
  for_each   = toset(var.policy_arns)
  role       = aws_iam_role.this.name
  policy_arn = each.value
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = 30
}

resource "aws_lambda_function" "this" {
  function_name    = var.function_name
  role             = aws_iam_role.this.arn
  handler          = var.handler
  runtime          = var.runtime
  filename         = var.filename
  source_code_hash = filebase64sha256(var.filename)
  layers           = var.layers
  timeout          = var.timeout
  memory_size      = var.memory_size

  environment {
    variables = var.environment_variables
  }

  depends_on = [aws_cloudwatch_log_group.this]
}

output "function_arn" { value = aws_lambda_function.this.arn }
output "function_name" { value = aws_lambda_function.this.function_name }
output "role_name" { value = aws_iam_role.this.name }
