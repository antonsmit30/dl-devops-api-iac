resource "aws_codepipeline" "dl-pipeline" {
  name     = "dl-api-pipeline"
  role_arn = aws_iam_role.dl-pipeline-role.arn

  artifact_store {
    location = aws_s3_bucket.dl-pipeline-bucket.bucket
    type     = "S3"
  }


  # Get commits
  stage {
    name = "Source"

    action {
      name     = "Source"
      category = "Source"
      owner    = "AWS"
      provider = "CodeStarSourceConnection"
      version  = "1"

      output_artifacts = ["SourceArtifact"]

      configuration = {
        ConnectionArn        = data.aws_codestarconnections_connection.dl-codestar-connection.id
        FullRepositoryId     = "antonsmit30/dl-devops-api"
        BranchName           = "development"
        OutputArtifactFormat = "CODE_ZIP"
      }

      namespace = "SourceVariables"
    }
  }

  # Build and Dockerize code
  stage {
    name = "Build"
    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["SourceArtifact"]
      output_artifacts = ["BuildArtifact"]
      version          = "1"

      configuration = {
        ProjectName = "${aws_codebuild_project.dl-devops-api-build.name}"
      }
    }
  }

  # Deploy Stage
  stage {
    name = "Deploy"
    action {
      name     = "Deploy"
      category = "Invoke"
      owner    = "AWS"
      provider = "Lambda"
      version  = "1"

      configuration = {
        FunctionName = aws_lambda_function.dl-lambda-deploy.function_name
      }

      input_artifacts  = ["BuildArtifact"]
      output_artifacts = ["outputartifacts"]

      region = "eu-west-1"
    }
  }

}

# S3 Bucket
resource "aws_s3_bucket" "dl-pipeline-bucket" {
  bucket        = "dl-pipeline-bucket"
  force_destroy = true
}

resource "aws_s3_bucket_acl" "dl-pipeline-bucket-acl" {
  bucket = aws_s3_bucket.dl-pipeline-bucket.id
  acl    = "private"
}

# IAM Service Role
resource "aws_iam_role" "dl-pipeline-role" {
  name = "dl-pipeline-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codepipeline.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "dl-pipeline-role-policy" {
  name = "dl-pipeline-role-policy"
  role = aws_iam_role.dl-pipeline-role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect":"Allow",
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:GetBucketVersioning",
        "s3:PutObjectAcl",
        "s3:PutObject"
      ],
      "Resource": [
        "${aws_s3_bucket.dl-pipeline-bucket.arn}",
        "${aws_s3_bucket.dl-pipeline-bucket.arn}/*"
      ]
    },
    {
        "Action": [
            "lambda:InvokeFunction",
            "lambda:ListFunctions"
        ],
        "Resource": "*",
        "Effect": "Allow"
    },
    {
      "Effect": "Allow",
      "Action": [
        "codestar-connections:UseConnection"
      ],
      "Resource": "${data.aws_codestarconnections_connection.dl-codestar-connection.id}"
    },
    {
      "Effect": "Allow",
      "Action": [
        "codebuild:BatchGetBuilds",
        "codebuild:StartBuild"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}