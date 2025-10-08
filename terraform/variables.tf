data "aws_availability_zones" "available" {}

locals {
  region = "us-east-1"
  name   = "ecs-assignment"
  aws_account_id = 446045858377

  vpc_cidr = "10.16.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  container_name = "flask-app"
  container_port = 8000

  tags = {
    Name       = local.name
    Example    = local.name
    Repository = "https://github.com/terraform-aws-modules/terraform-aws-ecs"
  }
}

