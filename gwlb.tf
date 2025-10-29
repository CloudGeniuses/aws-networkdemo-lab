############################################
# GWLB resources only (no variables here)
############################################

data "aws_caller_identity" "current" {}

resource "aws_lb" "gwlb" {
  name               = "${var.project_prefix}-gwlb"
  load_balancer_type = "gateway"

  subnets = [
    for id in values(var.private_subnet_ids) : id
  ]

  tags = {
    Name = "${var.project_prefix}-gwlb"
  }
}

resource "aws_lb_target_group" "gwlb_tg" {
  name        = "${var.project_prefix}-gwlb-tg"
  vpc_id      = var.vpc_id
  protocol    = "GENEVE"
  port        = 6081
  target_type = "ip"

  health_check {
    protocol            = "TCP"
    port                = "80"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
    timeout             = 5
  }

  tags = {
    Name = "${var.project_prefix}-gwlb-tg"
  }
}

resource "aws_lb_target_group_attachment" "gwlb_tg_attach" {
  for_each = {
    for index, endpoint in var.fw_endpoints : index => endpoint
  }

  target_group_arn  = aws_lb_target_group.gwlb_tg.arn
  target_id         = each.value.ip
  availability_zone = each.value.az
}

resource "aws_lb_listener" "gwlb_listener" {
  load_balancer_arn = aws_lb.gwlb.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gwlb_tg.arn
  }
}

resource "aws_vpc_endpoint_service" "gwlb_service" {
  acceptance_required = false

  gateway_load_balancer_arns = [
    aws_lb.gwlb.arn
  ]

  allowed_principals = [
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
  ]

  tags = {
    Name = "${var.project_prefix}-gwlb-svc"
  }
}

resource "aws_vpc_endpoint" "gwlbe" {
  for_each = var.private_subnet_ids

  vpc_id            = var.vpc_id
  service_name      = aws_vpc_endpoint_service.gwlb_service.service_name
  vpc_endpoint_type = "GatewayLoadBalancer"

  subnet_ids = [
    each.value
  ]

  tags = {
    Name = "${var.project_prefix}-gwlbe-${each.key}"
  }
}

resource "aws_route" "private_default_via_gwlbe" {
  for_each = var.private_route_table_ids

  route_table_id         = each.value
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = aws_vpc_endpoint.gwlbe[each.key].id
}
