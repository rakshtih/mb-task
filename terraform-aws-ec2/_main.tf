provider "aws" {
  region  = var.aws-region
  profile = var.aws-profile
}
data "aws_availability_zones" "available" {}

resource "aws_instance" "instance" {
  ami           = var.instance-ami
  instance_type = var.instance-type
  count = 2
  iam_instance_profile        = var.iam-role-name != "" ? var.iam-role-name : ""
  key_name                    = var.instance-key-name != "" ? var.instance-key-name : ""
  associate_public_ip_address = var.instance-associate-public-ip
  # user_data                   = "${file("${var.user-data-script}")}"
  user_data              = var.user-data-script != "" ? file("${var.user-data-script}") : ""
  vpc_security_group_ids = ["${aws_security_group.sg.id}"]
  subnet_id              = aws_subnet.subnet[count.index].id

  tags = {
    Name = "my-machine-${count.index}"
  }
}

resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc-cidr-block
  enable_dns_hostnames = true

  tags = {
    Name = "${var.vpc-tag-name}"
  }
}

resource "aws_internet_gateway" "ig" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.ig-tag-name}"
  }
}

resource "aws_subnet" "subnet" {
  count = 2
  vpc_id     = aws_vpc.vpc.id
  cidr_block = "10.0.${1+count.index}.0/24"#var.subnet-cidr-block 
  availability_zone = "${data.aws_availability_zones.available.names[count.index]}"
  tags = {
    Name = "${var.subnet-tag-name}"
  }
}

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ig.id
  }
}

resource "aws_route_table_association" "rta" {
  count = 2
  subnet_id      = aws_subnet.subnet[count.index].id
  route_table_id = aws_route_table.rt.id
}

resource "aws_security_group" "sg" {
  name   = var.sg-tag-name
  vpc_id = aws_vpc.vpc.id

  ingress {
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = "22"
    to_port     = "22"
  }

  ingress {
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = "80"
    to_port     = "80"
  }

  ingress {
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = "443"
    to_port     = "443"
  }

  ingress {
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = "8080"
    to_port     = "8080"
  }
  ingress {
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = "3000"
    to_port     = "3000"
  }
  egress {
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = "0"
    to_port     = "0"
  }

  tags = {
    Name = "${var.sg-tag-name}"
  }
}
resource "aws_lb" "alb" {
  name               = "mbition"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.sg.id]
  idle_timeout       = 60
  subnets            = [element(aws_subnet.subnet.*.id, 0), element(aws_subnet.subnet.*.id, 1)]
  #subnets            = [aws_subnet.subnet.id]
}

resource "aws_lb_target_group" "alb_target_group" {
  name        = "mbition"
  port        = 3000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.vpc.id

  health_check {
    enabled = true
    path = "/"
    port = "3000"
    protocol = "HTTP"
    healthy_threshold = 3
    unhealthy_threshold = 2
    interval = 90
    timeout = 20
    matcher = "200"
  }

  depends_on = [aws_lb.alb]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "3000"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_target_group.arn

  }
}

resource "aws_lb_target_group_attachment" "one" {
  count = length(aws_instance.instance)
  target_group_arn = aws_lb_target_group.alb_target_group.arn
  target_id        = aws_instance.instance[count.index].private_ip
  #target_id = [element(aws_instance.instance.*.private_ip, 0), element(aws_instance.instance.*.private_ip, 0)]
  port             = 3000
}