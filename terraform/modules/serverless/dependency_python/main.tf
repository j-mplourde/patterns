# serverless/dependency_python: a Lambda layer holding Python dependencies.
# Built outside Terraform (e.g. `pip install -r requirements.txt -t python/`)
# and referenced here by file path.

variable "layer_name" { type = string }
variable "filename" {
  type        = string
  description = "Path to the layer zip (contains python/...)."
}
variable "compatible_runtimes" {
  type    = list(string)
  default = ["python3.12"]
}

resource "aws_lambda_layer_version" "this" {
  layer_name          = var.layer_name
  filename            = var.filename
  source_code_hash    = filebase64sha256(var.filename)
  compatible_runtimes = var.compatible_runtimes
}

output "layer_arn" { value = aws_lambda_layer_version.this.arn }
