# ################################################################################
# # Cluster
# ################################################################################

# module "ecs_cluster" {
#   source = "terraform-aws-modules/ecs/aws//modules/cluster"

#   name = local.name

#   # Cluster capacity providers
#   # default_capacity_provider_strategy = {
#   #   on_demand = {
#   #     weight = 60
#   #     base   = 20
#   #   }
#   #   spot_fleet = {
#   #     weight = 40
#   #   }
#   # }

#   autoscaling_capacity_providers = {
#     # On-demand instances
#     on_demand = {
#       auto_scaling_group_arn         = module.autoscaling["on_demand"].autoscaling_group_arn
#       managed_draining               = "ENABLED"
#       managed_termination_protection = "ENABLED"

#       managed_scaling = {
#         maximum_scaling_step_size = 5
#         minimum_scaling_step_size = 1
#         status                    = "ENABLED"
#         target_capacity           = 60
#       }
#     }
#     # # Spot instances
#     # spot_fleet = {
#     #   auto_scaling_group_arn         = module.autoscaling["spot_fleet"].autoscaling_group_arn
#     #   managed_draining               = "ENABLED"
#     #   managed_termination_protection = "ENABLED"

#     #   managed_scaling = {
#     #     maximum_scaling_step_size = 15
#     #     minimum_scaling_step_size = 5
#     #     status                    = "ENABLED"
#     #     target_capacity           = 90
#     #   }
#     # }
#   }

#   tags = local.tags
# }

# ################################################################################
# # ECS Service
# ################################################################################
# module "ecs_service" {
#   source = "terraform-aws-modules/ecs/aws//modules/service"

#   # Basic service info
#   name        = local.name
#   cluster_arn = module.ecs_cluster.arn

#   # Deployment type
#   deployment_controller = {
#     type = "CODE_DEPLOY"
#   }

#   # EC2 launch
#   requires_compatibilities = ["EC2"]
#   capacity_provider_strategy = {
#     on_demand = {
#       capacity_provider = module.ecs_cluster.autoscaling_capacity_providers["on_demand"].name
#       weight            = 1
#       base              = 1
#     }
#   }

#   # Container definitions
#   container_definitions = {
#     (local.container_name) = {
#       image = "${aws_ecr_repository.flask_app_repo.repository_url}:latest"
#       portMappings = [
#         {
#           name          = local.container_name
#           containerPort = local.container_port
#           hostPort      = local.container_port
#           protocol      = "tcp"
#         }
#       ]

#       mountPoints = [
#         {
#           sourceVolume  = "my-vol"
#           containerPath = "/var/www/my-vol"
#         }
#       ]

#       readonlyRootFilesystem = false

#       enable_cloudwatch_logging              = true
#       create_cloudwatch_log_group            = true
#       cloudwatch_log_group_name              = "/aws/ecs/${local.name}/${local.container_name}"
#       cloudwatch_log_group_retention_in_days = 7

#       logConfiguration = {
#         logDriver = "awslogs"
#         options = {
#           awslogs-group         = "/aws/ecs/${local.name}/${local.container_name}"
#           awslogs-region        = "us-east-1"
#           awslogs-stream-prefix = "ecs"
#         }
#       }
#     }
#   }

#   # Volumes (ephemeral)
#   volume = {
#     my-vol = {}
#   }

#   # ALB integration
#   load_balancer = {
#     service = {
#       target_group_arn = aws_lb_target_group.tg[1].arn
#       container_name   = local.container_name
#       container_port   = local.container_port
#     }
#   }

#   subnet_ids = module.vpc.private_subnets

#   security_group_ingress_rules = {
#     alb_http = {
#       from_port                    = local.container_port
#       description                  = "Service port"
#       referenced_security_group_id = aws_security_group.application_elb_sg.id
#     }
#   }

#   tags = local.tags
# }

resource "aws_ecs_cluster" "app_cluster" {
  name = "application_cluster"
}

resource "aws_ecs_service" "flask" {
  name                               = "flask-service"
  cluster                            = aws_ecs_cluster.app_cluster.id
  task_definition                    = aws_ecs_task_definition.flask_task.arn
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 300
  launch_type                        = "EC2"
  scheduling_strategy                = "REPLICA"
  desired_count                      = 1


  force_new_deployment = true
  load_balancer {
    target_group_arn = aws_lb_target_group.tg[0].arn
    container_name   = "flask-app" 
    container_port   = "8000" # Application Port
  }
  deployment_controller {
    type = "CODE_DEPLOY"
  }


  # workaround for https://github.com/hashicorp/terraform/issues/12634
  depends_on = [aws_lb.app_lb]
  # we ignore task_definition changes as the revision changes on deploy
  # of a new version of the application
  # desired_count is ignored as it can change due to autoscaling policy
  lifecycle {
    ignore_changes = [task_definition, desired_count, load_balancer]
  }
}

resource "aws_ecs_task_definition" "flask_task" {
  family = "flask-task" 
  container_definitions = jsonencode([{
    name      = "flask-app",
    image     = "${aws_ecr_repository.flask_app_repo.repository_url}:latest",
    essential = true,
    portMappings = [
      {
        "containerPort" : 8000 # Application Port
      }
    ],




    # logConfiguration = {
    #   logDriver = "awslogs"
    # }
  }])
  requires_compatibilities = ["EC2"] # Stating that we are using ECS Fargate # Using awsvpc as our network mode as this is required for Fargate
  memory                   = 1800    # Specifying the memory our container requires
  cpu                      = 512     # Specifying the CPU our container requires
  execution_role_arn       = aws_iam_role.app_task_role.arn

}

resource "aws_iam_role" "app_task_role" {
  name = "app-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ECS_task_execution" {
  role       = aws_iam_role.app_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}