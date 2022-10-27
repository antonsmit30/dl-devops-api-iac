# Infrastructure for application
resource "aws_ecs_cluster" "dl-cluster" {
  name = "dl-cluster"
}

resource "aws_ecs_task_definition" "dl-service" {
  family = "dl-service"
  container_definitions = jsonencode([
    {
      name      = "dl-devops-api"
      image     = "${data.aws_ssm_parameter.dl-repo.value}:base"
      memory    = 256
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
        }
      ]
    }
  ])

  placement_constraints {
    type       = "memberOf"
    expression = "attribute:ecs.availability-zone in [eu-west-1a, eu-west-1c]"
  }
}

resource "aws_ecs_service" "dl-devops-api" {
  name            = "dl-devops-api"
  cluster         = aws_ecs_cluster.dl-cluster.id
  task_definition = data.aws_ecs_task_definition.dl-service.arn != "" ? data.aws_ecs_task_definition.dl-service.arn : aws_ecs_task_definition.dl-service.arn
  desired_count   = 2
  iam_role        = aws_iam_role.dl-devops-api-role.arn
  depends_on      = [aws_iam_role.dl-devops-api-role]

  load_balancer {
    target_group_arn = aws_lb_target_group.dl-alb-tg.arn
    container_name   = "dl-devops-api"
    container_port   = 80
  }

  placement_constraints {
    type       = "memberOf"
    expression = "attribute:ecs.availability-zone in [eu-west-1a, eu-west-1c]"
  }
}

# ECS service IAM permissions
resource "aws_iam_role" "dl-devops-api-role" {
  name = "dl-devops-api-service-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "dl-devops-api-service-policy" {
  name = "dl-devops-api-service"
  role = aws_iam_role.dl-devops-api-role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect":"Allow",
      "Action": [
        "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
        "elasticloadbalancing:DeregisterTargets",
        "elasticloadbalancing:Describe*",
        "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
        "elasticloadbalancing:RegisterTargets",
        "ec2:Describe*",
        "ec2:AuthorizeSecurityGroupIngress"
      ],
      "Resource": [
        "*"
      ]
    }
  ]
}
EOF
}

# ALB
resource "aws_lb" "dl-alb" {
  name               = "dl-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.dl-alb-sg.id]
  subnets            = [for s in data.aws_subnet.dl-subnet : s.id]

  tags = {
    Environment = "Devops"
  }
}

# ALB Listeners
resource "aws_lb_listener" "dl-alb-listener" {
  load_balancer_arn = aws_lb.dl-alb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type = "redirect"
      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
  }

}

resource "aws_lb_listener" "dl-alb-listener-ssl" {
  load_balancer_arn = aws_lb.dl-alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.tanontechcert.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dl-alb-tg.arn
  }
}

# ALB Target Group
resource "aws_lb_target_group" "dl-alb-tg" {
  name     = "dl-alb-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpcs.main-vpc.ids[0]
}


# Autoscaling group
resource "aws_autoscaling_group" "dl-asg" {
  name                      = "dl-asg"
  max_size                  = 2
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "ELB"
  desired_capacity          = 2
  force_delete              = true
  launch_configuration      = aws_launch_configuration.dl-asg-lc.name
  vpc_zone_identifier       = [for s in data.aws_subnet.dl-subnet : s.id]


  timeouts {
    delete = "15m"
  }

}

# launch configuration
resource "aws_launch_configuration" "dl-asg-lc" {
  name_prefix          = "dl-asg-lc-"
  image_id             = "ami-0c21ebd9e0dbd6249"
  instance_type        = "t2.micro"
  security_groups      = [aws_security_group.dl-alb-sg.id]
  iam_instance_profile = aws_iam_instance_profile.dl-asg-lc-profile.name
  key_name             = "antonawskey"
  user_data            = <<EOF
#!/bin/bash
echo "ECS_CLUSTER=${aws_ecs_cluster.dl-cluster.name}" >> /etc/ecs/ecs.config

EOF

}

# Launch configuration policies
resource "aws_iam_instance_profile" "dl-asg-lc-profile" {
  name = "dl-asg-lc-profile"
  role = aws_iam_role.dl-asg-lc-role.name
}

resource "aws_iam_role" "dl-asg-lc-role" {
  name = "dl-asg-lc-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "dl-asg-lc-role-policy" {
  name = "dl-asg-lc-role-policy"
  role = aws_iam_role.dl-asg-lc-role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect":"Allow",
      "Action": [
        "ecs:CreateCluster",
        "ecs:DeregisterContainerInstance",
        "ecs:DiscoverPollEndpoint",
        "ecs:Poll",
        "ecs:RegisterContainerInstance",
        "ecs:StartTelemetrySession",
        "ecs:Submit*",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": [
        "*"
      ]
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ec2container-attach" {
  role       = aws_iam_role.dl-asg-lc-role.name
  policy_arn = data.aws_iam_policy.ec2container.arn
}

# ALB SGs
resource "aws_security_group" "dl-alb-sg" {
  name        = "dl-alb-sg"
  description = "dl-alb-sg traffic on 80 and 443"
  vpc_id      = data.aws_vpcs.main-vpc.ids[0]

  ingress {
    description = "http"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ALB health ports"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [for s in data.aws_subnet.dl-subnet : s.cidr_block]
  }

  ingress {
    description = "https"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ALBPORTS"
    from_port   = 31000
    to_port     = 61000
    protocol    = "tcp"
    cidr_blocks = [for s in data.aws_subnet.dl-subnet : s.cidr_block]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

}

# A Record for routing to LB
resource "aws_route53_record" "dlapi-record" {
  zone_id = data.aws_route53_zone.dl-zone.id
  name    = "dlapi.${data.aws_route53_zone.dl-zone.name}"
  type    = "A"

  alias {
    name                   = aws_lb.dl-alb.dns_name
    zone_id                = aws_lb.dl-alb.zone_id
    evaluate_target_health = true
  }

}

#SSL Certificate
resource "aws_acm_certificate" "tanontechcert" {
  domain_name       = "*.${data.aws_route53_zone.dl-zone.name}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  validation_option {
    domain_name       = "*.${data.aws_route53_zone.dl-zone.name}"
    validation_domain = data.aws_route53_zone.dl-zone.name
  }
}