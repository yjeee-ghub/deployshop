#############################
# ECR Repositories
#############################

resource "aws_ecr_repository" "ecr-repo" {
  for_each = toset(var.repository_names)

  name = each.value

  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = each.value
  }
}


#############################
# ECR Lifecycle Policy
#############################

resource "aws_ecr_lifecycle_policy" "ecr_policy" {
  for_each = aws_ecr_repository.ecr-repo

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire only untagged images after 7 days; keep release tags for rollback"

        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }

        action = {
          type = "expire"
        }
      }
    ]
  })
}
