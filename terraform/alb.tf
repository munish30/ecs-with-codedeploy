################################################################################
# Load Balancer
################################################################################

data "aws_ssm_parameter" "ecs_optimized_ami" { name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended" }

resource "aws_security_group" "application_elb_sg" {
  vpc_id = module.vpc.vpc_id
  name   = "application_elb_sg"
}

# Only allow HTTP (port 80)
resource "aws_security_group_rule" "application_elb_sg_ingress" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.application_elb_sg.id
}

resource "aws_security_group_rule" "application_elb_sg_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.application_elb_sg.id
}

resource "aws_lb" "app_lb" {
  name               = "applicationLoadBalancer"
  load_balancer_type = "application"
  subnets            = module.vpc.public_subnets
  idle_timeout       = 60
  security_groups    = [aws_security_group.application_elb_sg.id]
}

################################################################################
# Target Groups for Blue/Green
################################################################################

locals {
  target_groups = [
    "blue",
    "green",
  ]
}

resource "aws_lb_target_group" "tg" {
  count = length(local.target_groups)

  name        = "tg-${element(local.target_groups, count.index)}"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = module.vpc.vpc_id

  health_check {
    path                = "/"
    matcher             = "200,301,302,404"
    interval            = 30
    healthy_threshold   = 3
    unhealthy_threshold = 2
    timeout             = 5
  }
}

################################################################################
# HTTP Listener
################################################################################

resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg[0].arn # Blue TG initially
  }

  depends_on = [aws_lb_target_group.tg]

  lifecycle {
    ignore_changes = [default_action] # Allow CodeDeploy to change during deploys
  }
}
