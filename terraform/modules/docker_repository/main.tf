# docker_repository: ECR repository with a lifecycle policy that keeps the most
# recent N images and prunes the rest. Lives in the OPERATIONS-TOOLING account
# so that every workload pulls from the same hardened image registry.

variable "name" { type = string }
variable "keep_last_n_images" {
  type    = number
  default = 50
}

resource "aws_ecr_repository" "this" {
  name = var.name

  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "KMS" }
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last ${var.keep_last_n_images} images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = var.keep_last_n_images
      }
      action = { type = "expire" }
    }]
  })
}

output "repository_url" { value = aws_ecr_repository.this.repository_url }
output "repository_arn" { value = aws_ecr_repository.this.arn }
