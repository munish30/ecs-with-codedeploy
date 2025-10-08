################################################################################
# Cluster
################################################################################

module "ecs_cluster" {
  source = "terraform-aws-modules/ecs/aws//modules/cluster"

  name = local.name

  # Cluster capacity providers
  # default_capacity_provider_strategy = {
  #   on_demand = {
  #     weight = 60
  #     base   = 20
  #   }
  #   spot_fleet = {
  #     weight = 40
  #   }
  # }

  autoscaling_capacity_providers = {
    # On-demand instances
    on_demand = {
      auto_scaling_group_arn         = module.autoscaling["on_demand"].autoscaling_group_arn
      managed_draining               = "ENABLED"
      managed_termination_protection = "ENABLED"

      managed_scaling = {
        maximum_scaling_step_size = 5
        minimum_scaling_step_size = 1
        status                    = "ENABLED"
        target_capacity           = 60
      }
    }
    # # Spot instances
    # spot_fleet = {
    #   auto_scaling_group_arn         = module.autoscaling["spot_fleet"].autoscaling_group_arn
    #   managed_draining               = "ENABLED"
    #   managed_termination_protection = "ENABLED"

    #   managed_scaling = {
    #     maximum_scaling_step_size = 15
    #     minimum_scaling_step_size = 5
    #     status                    = "ENABLED"
    #     target_capacity           = 90
    #   }
    # }
  }

  tags = local.tags
}

################################################################################
# Service
################################################################################

module "ecs_service" {
  source = "terraform-aws-modules/ecs/aws//modules/service"

  # Service
  name        = local.name
  cluster_arn = module.ecs_cluster.arn

  # Task Definition
  requires_compatibilities = ["EC2"]
  capacity_provider_strategy = {
    # On-demand instances
    on_demand = {
      capacity_provider = module.ecs_cluster.autoscaling_capacity_providers["on_demand"].name
      weight            = 1
      base              = 1
    }
  }

  volume_configuration = {
    name = "ebs-volume"
    managed_ebs_volume = {
      encrypted        = true
      file_system_type = "xfs"
      size_in_gb       = 5
      volume_type      = "gp3"
    }
  }

  volume = {
    my-vol = {},
    ebs-volume = {
      name                = "ebs-volume"
      configure_at_launch = true
    }
  }

  # Container definition(s)
  container_definitions = {
    (local.container_name) = {
      image = "${aws_ecr_repository.flask_app_repo.repository_url}:latest"
      portMappings = [
        {
          name          = local.container_name
          containerPort = local.container_port
          hostPort      = local.container_port
          protocol      = "tcp"
        }
      ]

      mountPoints = [
        {
          sourceVolume  = "my-vol",
          containerPath = "/var/www/my-vol"
        },
        {
          sourceVolume  = "ebs-volume"
          containerPath = "/ebs/data"
        }
      ]

      # entrypoint = ["/usr/sbin/apache2", "-D", "FOREGROUND"]

      # Example image used requires access to write to root filesystem
      readonlyRootFilesystem = false

      enable_cloudwatch_logging              = true
      create_cloudwatch_log_group            = true
      cloudwatch_log_group_name              = "/aws/ecs/${local.name}/${local.container_name}"
      cloudwatch_log_group_retention_in_days = 7

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/aws/ecs/${local.name}/${local.container_name}"
          awslogs-region        = "us-east-1" # Change to your region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  }

  load_balancer = {
    service = {
      target_group_arn = module.alb.target_groups["ex_ecs"].arn
      container_name   = local.container_name
      container_port   = local.container_port
    }
  }

  subnet_ids = module.vpc.private_subnets
  security_group_ingress_rules = {
    alb_http = {
      from_port                    = local.container_port
      description                  = "Service port"
      referenced_security_group_id = module.alb.security_group_id
    }
  }

  tags = local.tags
}
