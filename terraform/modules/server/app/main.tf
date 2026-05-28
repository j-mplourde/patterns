# server/app: the production-shape EC2 host that runs the workload's container
# stack via docker-compose, fronted by Traefik (see ansible/ for the deploy
# side). Includes the SSM-friendly instance profile and the EC2 tags Ansible
# uses for inventory discovery (Product=EC2, Service=<project>).

variable "project" { type = string }
variable "environment" { type = string }
variable "ami_id" { type = string }
variable "instance_type" {
  type    = string
  default = "t3.medium"
}
variable "subnet_id" { type = string }
variable "security_group_ids" { type = list(string) }
variable "log_group_name" { type = string }

resource "aws_iam_role" "instance" {
  name = "${var.project}-${var.environment}-app"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# SSM Session Manager + CloudWatch Logs - no SSH ports open anywhere.
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
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

  metadata_options {
    http_tokens               = "required" # IMDSv2 only
    http_put_response_hop_limit = 2
  }

  tags = {
    Name     = "${var.project}-${var.environment}"
    Product  = "EC2"          # <- consumed by Ansible aws_ec2 inventory plugin
    Service  = var.project    # <- consumed by Ansible aws_ec2 inventory plugin
    LogGroup = var.log_group_name
  }
}

output "instance_id" { value = aws_instance.this.id }
output "private_ip" { value = aws_instance.this.private_ip }
