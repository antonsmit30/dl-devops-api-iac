# Dev env lambda function
resource "aws_iam_role" "dl-lambda-deploy-role" {
  name = "dl-lambda-deploy-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "dl-lambda-deploy-policy" {
  name = "dl-lambda-deploy-policy"
  role = aws_iam_role.dl-lambda-deploy-role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect":"Allow",
      "Action": [
        "codepipeline:PutJobSuccessResult",
        "codepipeline:PutJobFailureResult",
        "ssm:GetParameter",
        "ecs:RegisterTaskDefinition",
        "ecs:UpdateService",
        "ecs:UpdateCluster",
        "ecs:UpdateClusterSettings",
        "ecs:UpdateServicePrimaryTaskSet"
      ],
      "Resource": [
        "*"
      ]
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "dl-lambda-deploy-policy-logging" {
  name = "dl-lambda-deploy-policy-logging"
  role = aws_iam_role.dl-lambda-deploy-role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect":"Allow",
      "Action": [
        "logs:*"
      ],
      "Resource": [
        "arn:aws:logs:*:*:*"
      ]
    }
  ]
}
EOF
}

data "archive_file" "dl-lambda-inline" {
  type        = "zip"
  output_path = "./files/lambda_zip_inline.zip"
  source {
    content  = <<EOF
import json
import boto3

def lambda_handler(event, context):

    # Initiate Clients for ecs and codepipeline and ssm
    ecs_client = boto3.client('ecs')
    ssm_client = boto3.client('ssm')
    ssm_response = ssm_client.get_parameter(Name='/DL-API/REPO/VERSION')
    app_version = ssm_response['Parameter']['Value']
    pipeline_client = boto3.client('codepipeline')
    job_id = event['CodePipeline.job']['id']

    try:
        ssm_response = ssm_client.get_parameter(Name='/DL-API/REPO/VERSION')
        app_version = ssm_response['Parameter']['Value']

        # create new ECS task definition
        task_definition_response = ecs_client.register_task_definition(
            family="dl-service",
            containerDefinitions=[
                {
                    "name": "dl-devops-api",
                    "image": "${data.aws_ssm_parameter.dl-repo.value}:{}".format(app_version),
                    "memory": 256,
                    "links": [],
                    "portMappings": [
                        {
                            "containerPort": 80,
                            "hostPort": 0,
                            "protocol": "tcp"
                        }
                    ]
                }])

        # call ECS service
        response = ecs_client.update_service(
            cluster='${aws_ecs_cluster.dl-cluster.name}',
            service='${aws_ecs_service.dl-devops-api.name}',
            taskDefinition='${aws_ecs_task_definition.dl-service.family}',
            forceNewDeployment=True
            )

        # if success inform codepipeline
        pipeline_response = pipeline_client.put_job_success_result(jobId=job_id)

        return {
            'statusCode': 200,
            'body': "Success"
        }
    except Exception as e:
        print(e)

        pipeline_response = pipeline_client.put_job_failure_result(
            jobId=job_id,
            failureDetails={
                'type': 'JobFailed',
                'message': str(e)
            }
        )

        return {
            'statusCode': 500,
            'body': str(e)
        }
EOF
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "dl-lambda-deploy" {

  filename         = data.archive_file.dl-lambda-inline.output_path
  source_code_hash = data.archive_file.dl-lambda-inline.output_base64sha256
  function_name    = "dl-lambda-deploy-${aws_ecs_cluster.dl-cluster.name}"
  role             = aws_iam_role.dl-lambda-deploy-role.arn
  handler          = "lambda_function.lambda_handler"

  runtime = "python3.8"

}