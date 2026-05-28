# server/app_simplified: the smaller cousin of server/app, used in non-prod
# environments where the full ALB/multi-AZ shape is overkill. Same SSM-only
# access pattern. Useful when dev-cost matters more than HA.

variable "project" { type = string }
variable "environment" { type = string }
variable "ami_id" { type = string }
variable "instance_type" {
  type    = string
  default = "t3.small"
}
variable "subnet_id" { type = string }
variable "security_group_ids" { type = list(string) }

resource "aws_iam_role" "instance" {
  name = "${var.project}-${var.environment}-app-simple"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_instance_profile" "this" {
  name = aws_iam_role.instance.name
  role = aws_iam_role.instance.name
}

resource "aws_instance" "this" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids
  iam_instance_profile   = aws_iam_instance_profile.this.name

  metadata_options { http_tokens = "required" }

  tags = {
    Name    = "${var.project}-${var.environment}"
    Product = "EC2"
    Service = var.project
  }
}

output "instance_id" { value = aws_instance.this.id }
