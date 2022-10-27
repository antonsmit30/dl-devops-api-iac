# CODEBUILD CONFIGURATION
resource "aws_codebuild_project" "dl-devops-api-build" {
  name          = "dl-devops-api-build"
  description   = "Codebuild project for dl-devops-api"
  build_timeout = "5"
  service_role  = aws_iam_role.dl-build-role.arn

  artifacts {
    type = "NO_ARTIFACTS"
  }

  cache {
    type = "NO_CACHE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:3.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true

    environment_variable {
      name  = "BranchName"
      value = "development"
    }

  }

  logs_config {
    cloudwatch_logs {
      group_name  = "log-group"
      stream_name = "log-stream"
    }

    s3_logs {
      status   = "ENABLED"
      location = "${aws_s3_bucket.dl-build-bucket.id}/build-log"
    }
  }

  source {
    type            = "GITHUB"
    location        = "https://github.com/antonsmit30/dl-devops-api.git"
    git_clone_depth = 1

    git_submodules_config {
      fetch_submodules = true
    }
  }

  source_version = "development"


  tags = {
    Environment = "Devops"
  }
}



# S3 BUCKET CONFIGS
resource "aws_s3_bucket" "dl-build-bucket" {
  bucket        = "dl-build-bucket"
  force_destroy = true
}

resource "aws_s3_bucket_acl" "dl-build-bucket-acl" {
  bucket = aws_s3_bucket.dl-build-bucket.id
  acl    = "private"
}

# IAM to access pipeline, s3
resource "aws_iam_role" "dl-build-role" {
  name = "dl-build-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codebuild.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

# Service Policies
resource "aws_iam_role_policy" "dl-build-service-policy" {
  role = aws_iam_role.dl-build-role.name

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Resource": [
                "arn:aws:logs:eu-west-1:${data.aws_caller_identity.current.account_id}:*"
            ],
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ]
        },
        {
            "Effect": "Allow",
            "Resource": [
                "arn:aws:ssm:eu-west-1:386659630225*"
            ],
            "Action": [
                "ssm:*"
            ]
        },
        {
            "Effect": "Allow",
            "Resource": [
                "*"
            ],
            "Action": [
                "ecr:*"
            ]
        },
        {
            "Effect": "Allow",
            "Resource": [
                "arn:aws:s3:::codepipeline-eu-west-1-*",
                "arn:aws:s3:::dl-pipeline-bucket*"
            ],
            "Action": [
                "s3:PutObject",
                "s3:GetObject",
                "s3:GetObjectVersion",
                "s3:GetBucketAcl",
                "s3:GetBucketLocation"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "codebuild:CreateReportGroup",
                "codebuild:CreateReport",
                "codebuild:UpdateReport",
                "codebuild:BatchPutTestCases",
                "codebuild:BatchPutCodeCoverages"
            ],
            "Resource": [
                "arn:aws:codebuild:eu-west-1:${data.aws_caller_identity.current.account_id}:*"
            ]
        }
    ]
}
EOF
}