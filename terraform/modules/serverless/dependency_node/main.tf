# serverless/dependency_node: a Lambda layer holding the workload's Node.js
# dependencies. Built outside Terraform (e.g. by the CI pipeline running
# `pnpm install --prod`) and referenced here by file path.

variable "layer_name" { type = string }
variable "filename" {
  type        = string
  description = "Path to the layer zip (contains nodejs/node_modules/...)."
}
variable "compatible_runtimes" {
  type    = list(string)
  default = ["nodejs22.x"]
}

resource "aws_lambda_layer_version" "this" {
  layer_name          = var.layer_name
  filename            = var.filename
  source_code_hash    = filebase64sha256(var.filename)
  compatible_runtimes = var.compatible_runtimes
}

output "layer_arn" { value = aws_lambda_layer_version.this.arn }
