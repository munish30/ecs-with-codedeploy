module "autoscaling" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "~> 9.0"

  for_each = {
    # On-demand instances
    on_demand = {
      instance_type              = "t3.medium"
      use_mixed_instances_policy = false
      mixed_instances_policy     = null
      user_data                  = <<-EOT
        #!/bin/bash

        cat <<'EOF' >> /etc/ecs/ecs.config
        ECS_CLUSTER=${local.name}
        ECS_LOGLEVEL=debug
        ECS_CONTAINER_INSTANCE_TAGS=${jsonencode(local.tags)}
        ECS_ENABLE_TASK_IAM_ROLE=true
        EOF
      EOT
    }
    # # Spot instances
    # spot_fleet = {
    #   instance_type              = "t3.medium"
    #   use_mixed_instances_policy = true
    #   mixed_instances_policy = {
    #     instances_distribution = {
    #       on_demand_base_capacity                  = 0
    #       on_demand_percentage_above_base_capacity = 0
    #       spot_allocation_strategy                 = "price-capacity-optimized"
    #     }

    #     launch_template = {
    #       override = [
    #         {
    #           instance_type     = "t3.medium"
    #           weighted_capacity = "2"
    #         }
    #       ]
    #     }
    #   }
    #   user_data = <<-EOT
    #     #!/bin/bash

    #     cat <<'EOF' >> /etc/ecs/ecs.config
    #     ECS_CLUSTER=${local.name}
    #     ECS_LOGLEVEL=debug
    #     ECS_CONTAINER_INSTANCE_TAGS=${jsonencode(local.tags)}
    #     ECS_ENABLE_TASK_IAM_ROLE=true
    #     ECS_ENABLE_SPOT_INSTANCE_DRAINING=true
    #     EOF
    #   EOT
    # }
  }

  name = "${local.name}-${each.key}"

  image_id      = jsondecode(data.aws_ssm_parameter.ecs_optimized_ami.value)["image_id"]
  instance_type = each.value.instance_type

  security_groups                 = [module.autoscaling_sg.security_group_id]
  user_data                       = base64encode(each.value.user_data)
  ignore_desired_capacity_changes = true

  create_iam_instance_profile = true
  iam_role_name               = local.name
  iam_role_description        = "ECS role for ${local.name}"
  iam_role_policies = {
    AmazonEC2ContainerServiceforEC2Role = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
    AmazonSSMManagedInstanceCore        = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  vpc_zone_identifier = module.vpc.private_subnets
  health_check_type   = "EC2"
  min_size            = 1
  max_size            = 5
  desired_capacity    = 2

  # https://github.com/hashicorp/terraform-provider-aws/issues/12582
  autoscaling_group_tags = {
    AmazonECSManaged = true
  }

  # Required for  managed_termination_protection = "ENABLED"
  protect_from_scale_in = true

  # Spot instances
  use_mixed_instances_policy = each.value.use_mixed_instances_policy
  mixed_instances_policy     = each.value.mixed_instances_policy

  tags = local.tags
}

module "autoscaling_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = local.name
  description = "Autoscaling group security group"
  vpc_id      = module.vpc.vpc_id

  computed_ingress_with_source_security_group_id = [
    {
      rule                     = "http-80-tcp"
      source_security_group_id = module.alb.security_group_id
    }
  ]
  number_of_computed_ingress_with_source_security_group_id = 1

  egress_rules = ["all-all"]

  tags = local.tags
}