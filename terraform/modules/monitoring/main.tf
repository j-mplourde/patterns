# monitoring: per-workload CloudWatch dashboard. A single source of truth for
# the health metrics on-call needs to see, defined in code next to the resources
# it observes.

variable "project" { type = string }
variable "environment" { type = string }
variable "region" { type = string }
variable "alb_arn_suffix" {
  type    = string
  default = ""
}

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = "${var.project}-${var.environment}"
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          title  = "ALB request count"
          region = var.region
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix],
          ]
          stat   = "Sum"
          period = 60
        }
      },
    ]
  })
}

output "dashboard_arn" { value = aws_cloudwatch_dashboard.this.dashboard_arn }
