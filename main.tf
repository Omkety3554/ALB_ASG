# We will start with defining aws provider and setting up version constraints for the provider and terraform itself.
provider "aws" {
  region = "us-east-1"
  profile = "muqodas"
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.30.0"
    }
  }

  required_version = "~> 1.0"
}


# Then the VPC resource with CIDR range /16, which will give us around 65 thousand IP addresses.
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "main"
  }
}

# Internet Gateway to provide internet access for public subnets
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "igw"
  }
}

# Then let's define two private and two public subnets.


resource "aws_subnet" "private_us_east_1a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.0.0/19"
  availability_zone = "us-east-1a"

  tags = {
    "Name" = "private-us-east-1a"
  }
}

resource "aws_subnet" "private_us_east_1b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.32.0/19"
  availability_zone = "us-east-1b"

  tags = {
    "Name" = "private-us-east-1b"
  }
}

resource "aws_subnet" "public_us_east_1a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.64.0/19"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    "Name" = "public-us-east-1a"
  }
}

resource "aws_subnet" "public_us_east_1b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.96.0/19"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    "Name" = "public-us-east-1b"
  }
}

# NAT Gateway to provide Internet access in private subnets along with Elastic IP address.
resource "aws_eip" "nat" {
  vpc = true

  tags = {
    Name = "nat"
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_us_east_1a.id

  tags = {
    Name = "nat"
  }

  depends_on = [aws_internet_gateway.igw]
}

# Finally, the route tables to associate private subnets with NAT Gateway and public subnets with Internet Gateway.


resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "private"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public"
  }
}

resource "aws_route_table_association" "private_us_east_1a" {
  subnet_id      = aws_subnet.private_us_east_1a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_us_east_1b" {
  subnet_id      = aws_subnet.private_us_east_1b.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "public_us_east_1a" {
  subnet_id      = aws_subnet.public_us_east_1a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_us_east_1b" {
  subnet_id      = aws_subnet.public_us_east_1b.id
  route_table_id = aws_route_table.public.id
}


# we will attach an application load balancer to the auto-scaling group. Based on the load, it can scale up or down the number of EC2 instances to handle the traffic.
# create security group
resource "aws_security_group" "ec2_eg2" {
  name   = "ec2-eg2"
  vpc_id = aws_vpc.main.id
}

resource "aws_security_group" "alb_eg2" {
  name   = "alb-eg2"
  vpc_id = aws_vpc.main.id
}

# firewall rules for the EC2 security group.


resource "aws_security_group_rule" "ingress_ec2_eg2_traffic" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  security_group_id        = aws_security_group.ec2_eg2.id
  source_security_group_id = aws_security_group.alb_eg2.id
}

resource "aws_security_group_rule" "ingress_ec2_eg2_health_check" {
  type                     = "ingress"
  from_port                = 8081
  to_port                  = 8081
  protocol                 = "tcp"
  security_group_id        = aws_security_group.ec2_eg2.id
  source_security_group_id = aws_security_group.alb_eg2.id
}

# resource "aws_security_group_rule" "full_egress_ec2_eg2" {
#   type              = "egress"
#   from_port         = 0
#   to_port           = 0
#   protocol          = "-1"
#   security_group_id = aws_security_group.ec2_eg2.id
#   cidr_blocks       = ["0.0.0.0/0"]
# }

# Now for the application load balancer, we need to open an additional 443 port to handle HTTPS traffic.


resource "aws_security_group_rule" "ingress_alb_eg2_http_traffic" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  security_group_id = aws_security_group.alb_eg2.id
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "ingress_alb_eg2_https_traffic" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.alb_eg2.id
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "egress_alb_eg2_traffic" {
  type                     = "egress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  security_group_id        = aws_security_group.alb_eg2.id
  source_security_group_id = aws_security_group.ec2_eg2.id
}

resource "aws_security_group_rule" "egress_alb_eg2_health_check" {
  type                     = "egress"
  from_port                = 8081
  to_port                  = 8081
  protocol                 = "tcp"
  security_group_id        = aws_security_group.alb_eg2.id
  source_security_group_id = aws_security_group.ec2_eg2.id
}

# Instead of creating EC2 instances, we need to define launch_template. The auto-scaling group will use it to spin up new VMs.
resource "aws_launch_template" "my_app_eg2" {
  name                   = "my-app-eg2"
  image_id               = "ami-07309549f34230bcd"
  key_name               = "devops"
  vpc_security_group_ids = [aws_security_group.ec2_eg2.id]
}

# The target group and a health check are exactly the same
resource "aws_lb_target_group" "my_app_eg2" {
  name     = "my-app-eg2"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    port                = 8081
    interval            = 30
    protocol            = "HTTP"
    path                = "/health"
    matcher             = "200"
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

# The auto-scaling group will be responsible for creating and registering new EC2 instances with the load balancer.

# You can specify min and max sizes for the group, but it's not enough to scale it automatically. It just defines the boundaries.
# We want to create a load balancer in public subnets, but for the nodes, we want to keep them in private subnets without direct internet access.
# To register this auto-scaling group with the target group, use target_group_arns.
# Then provide the launch_template, and you can override the default instance_type, such as t3.micro.



resource "aws_autoscaling_group" "my_app_eg2" {
  name     = "my-app-eg2"
  min_size = 2
  max_size = 5

  health_check_type = "EC2"

  vpc_zone_identifier = [
    aws_subnet.private_us_east_1a.id,
    aws_subnet.private_us_east_1b.id
  ]

  target_group_arns = [aws_lb_target_group.my_app_eg2.arn]

  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.my_app_eg2.id
      }
      override {
        instance_type = "t3.micro"
      }
    }
  }
}

# To dynamically scale your auto-scaling group, you need to define a policy. In this, we use CPU as a threshold. If the average CPU usage across all virtual machines exceeds 25%, add an additional EC2 instance. In production, you would set it closer to 80%
resource "aws_autoscaling_policy" "my_app_eg2" {
  name                   = "my-app-eg2"
  policy_type            = "TargetTrackingScaling"
  autoscaling_group_name = aws_autoscaling_group.my_app_eg2.name

  estimated_instance_warmup = 300

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 25.0
  }
}

# Next is the same load balancer resource; the only difference for this load balancer is that we open an additional 443 port in the security group.
resource "aws_lb" "my_app_eg2" {
  name               = "my-app-eg2"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_eg2.id]

  subnets = [
    aws_subnet.public_us_east_1a.id,
    aws_subnet.public_us_east_1b.id
  ]
}


# Now the listener, let's start with the same port 80. Sometimes you have a requirement to accept the HTTP requests on port 80 and redirect them to secured port 443.
resource "aws_lb_listener" "my_app_eg2" {
  load_balancer_arn = aws_lb.my_app_eg2.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.my_app_eg2.arn
  }
}

# Let's apply the terraform again and test the application load balancer
