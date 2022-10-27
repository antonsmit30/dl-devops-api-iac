# Setup Repo for application
resource "aws_ecr_repository" "dl-devops-api-repo" {
  name                 = "dl-devops-api"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false
  }
}

resource "aws_ecr_lifecycle_policy" "dl-devops-api-repo-lf-policy" {
  repository = aws_ecr_repository.dl-devops-api-repo.name

  policy = <<EOF
{
    "rules": [
        {
            "rulePriority": 1,
            "description": "Keep last 10 images with master tags (prod)",
            "selection": {
                "tagStatus": "tagged",
                "tagPrefixList": ["master-"],
                "countType": "imageCountMoreThan",
                "countNumber": 10
            },
            "action": {
                "type": "expire"
            }
        },
        {
            "rulePriority": 2,
            "description": "Keep last 10 images with development tags",
            "selection": {
                "tagStatus": "tagged",
                "tagPrefixList": ["development-"],
                "countType": "imageCountMoreThan",
                "countNumber": 10
            },
            "action": {
                "type": "expire"
            }
        }
    ]
}
EOF
}