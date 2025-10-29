############################################
# Phase 3 — Gateway Load Balancer (GWLB)
# - Reuses VPC / subnets / RTs from main.tf
# - Only input needed: fw_endpoints (IP + AZ)
############################################

# Only variable we still need: the firewall target IPs + AZ
variable "fw_endpoints" {
  description = <<EOT
List of firewall dataplane IPs (targets) with their AZ.
Example:
[
  { ip = "10.10.2.50", az = "us-west-2a" },
  # add another when second FW is deployed:
  # { ip = "10.10.4.50", az = "us-west-2b" }
]
EOT
  type = list(object({
    ip = string
    az = string
  }))
}

data "aws_caller_identity" "current" {}

############################################
# Locals pulling from your existing resources
############################################
locals {
  vpc_id = aws_vpc.this.id

  private_subnet_ids = {
    a = aws_subnet.private_a.id
    b = aws_subnet.private_b.id
  }

  private_route_table_ids = {
    a = aws_route_table.private_a.id
    b = aws_route_table.private_b.id
  }
}

############################################
# GWLB + Target Group (GENEVE/6081)
############################################
resource "aws_lb" "gwlb" {
  name               = "${var.project_prefix}-gwlb"
  load_balancer_type = "gateway"
  subnets            = values(local.private_subnet_ids)

  tags = {
    Name = "${var.project_prefix}-gwlb"
  }
}

resource "aws_lb_target_group" "gwlb_tg" {
  name        = "${var.project_prefix}-gwlb-tg"
  vpc_id      = local.vpc_id
  protocol    = "GENEVE"
  port        = 6081
  target_type = "ip"

  # PAN GWLB health responder listens on TCP/80 by default
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
  for_each          = { for i, t in var.fw_endpoints : i => t }
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

############################################
# Publish GWLB as an Endpoint Service
############################################
resource "aws_vpc_endpoint_service" "gwlb_service" {
  acceptance_required        = false
  gateway_load_balancer_arns = [aws_lb.gwlb.arn]
  allowed_principals         = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]

  tags = {
    Name = "${var.project_prefix}-gwlb-svc"
  }
}

############################################
# Create GWLBe in each private subnet
############################################
resource "aws_vpc_endpoint" "gwlbe" {
  for_each          = local.private_subnet_ids
  vpc_id            = local.vpc_id
  service_name      = aws_vpc_endpoint_service.gwlb_service.service_name
  vpc_endpoint_type = "GatewayLoadBalancer"
  subnet_ids        = [each.value]

  tags = {
    Name = "${var.project_prefix}-gwlbe-${each.key}"
  }
}

############################################
# Route private RTs: 0.0.0.0/0 -> GWLBe
############################################
resource "aws_route" "private_default_via_gwlbe" {
  for_each               = local.private_route_table_ids
  route_table_id         = each.value
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = aws_vpc_endpoint.gwlbe[each.key].id
}
