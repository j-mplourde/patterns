# server/image_builder: EC2 Image Builder pipeline that bakes a hardened AMI
# (CIS-aligned, SSM agent + Docker + CloudWatch agent pre-installed) used by
# `server/app`. Lives in the OPERATIONS-TOOLING account; the AMI is shared with
# workload accounts via launch permissions.

variable "name" { type = string }
variable "parent_image" {
  type        = string
  default     = "arn:aws:imagebuilder:ca-central-1:aws:image/amazon-linux-2023-x86/x.x.x"
  description = "Parent image ARN to base the recipe on."
}
variable "component_arns" {
  type        = list(string)
  default     = []
  description = "Custom build component ARNs to layer on top of the parent."
}
variable "share_with_account_ids" {
  type    = list(string)
  default = []
}

resource "aws_imagebuilder_image_recipe" "this" {
  name         = var.name
  parent_image = var.parent_image
  version      = "1.0.0"

  dynamic "component" {
    for_each = var.component_arns
    content { component_arn = component.value }
  }
}

resource "aws_imagebuilder_infrastructure_configuration" "this" {
  name                          = "${var.name}-infra"
  instance_profile_name         = "EC2InstanceProfileForImageBuilder"
  terminate_instance_on_failure = true
}

resource "aws_imagebuilder_distribution_configuration" "this" {
  name = "${var.name}-dist"

  distribution {
    region = data.aws_region.current.name
    ami_distribution_configuration {
      name = "${var.name}-{{ imagebuilder:buildDate }}"
      launch_permission {
        user_ids = var.share_with_account_ids
      }
    }
  }
}

resource "aws_imagebuilder_image_pipeline" "this" {
  name                             = var.name
  image_recipe_arn                 = aws_imagebuilder_image_recipe.this.arn
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.this.arn
  distribution_configuration_arn   = aws_imagebuilder_distribution_configuration.this.arn

  schedule {
    schedule_expression = "cron(0 8 ? * mon)"
  }
}

data "aws_region" "current" {}

output "pipeline_arn" { value = aws_imagebuilder_image_pipeline.this.arn }
