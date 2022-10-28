data "aws_caller_identity" "current" {}

output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

data "aws_vpcs" "main-vpc" {
  tags = {
    Environment = "Devops"
  }
}

output "main-vpc" {
  value = data.aws_vpcs.main-vpc.ids
}


data "aws_subnets" "vpc-subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpcs.main-vpc.ids[0]]
  }

  tags = {
    env = "public"
  }

}

data "aws_subnet" "dl-subnet" {
  for_each = toset(data.aws_subnets.vpc-subnets.ids)
  id       = each.value
}

output "subnet_cidr_blocks" {
  value = [for s in data.aws_subnet.dl-subnet : s.cidr_block]
}

output "subnet_ids" {
  value = [for s in data.aws_subnet.dl-subnet : s.id]
}

data "aws_ssm_parameter" "dl-repo" {
  name = "/DL-API/REPO"
}


# AWS managed policies
data "aws_iam_policy" "ec2container" {
  name = "AmazonEC2ContainerServiceforEC2Role"
}

# Hosted Zone
data "aws_route53_zone" "dl-zone" {
  name = "tanontechworld.com."
}

output "dl-hosted-zone" {
  value = data.aws_route53_zone.dl-zone
}

data "aws_ecs_task_definition" "dl-service" {
  task_definition = aws_ecs_task_definition.dl-service.family
}

output "dl-service" {
  value = data.aws_ecs_task_definition.dl-service
}

data "aws_codestarconnections_connection" "dl-codestar-connection" {
  name = "my-github-connection"
}

output "codestar_details" {
  value = data.aws_codestarconnections_connection.dl-codestar-connection.id
}