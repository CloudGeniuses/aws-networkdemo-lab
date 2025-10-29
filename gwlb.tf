############################################
# Phase 3 — Gateway Load Balancer (GWLB)
# - GWLB + Target Group (GENEVE/6081)
# - Register FW dataplane IPs as targets
# - GWLBe per private subnet
# - Private RTs: 0.0.0.0/0 -> GWLBe
############################################

variable "project_prefix" {
  type    = string
  default = "cg-adv"
}

variable "vpc_id" {
  description = "VPC ID that hosts the GWLB and endpoints"
  type        = string
}

variable "private_subnet_ids" {
  description = "Map of private subnet IDs by AZ key (e.g., { a = subnet-xxx, b = subnet-yyy })"
  type        = map(string)
}

variable "private_route_table_ids" {
  description = "Map of private route table IDs by AZ key (e.g., { a = rtb-xxx, b = rtb-yyy })"
  type        = map(string)
}

variable "fw_endpoints" {
  description = <<EOT
List of firewall dataplane target IPs with their AZs for GWLB target group.
Example:
[
  { ip = "10.10.2.50", az = "us-west-2a" },
  { ip = "10.10.4.50", az = "us-west-2b" }
]
EOT
  type = list(object({
    ip = string
    az = string
  }))
}

data "aws_caller_identity" "this" {}

############################################
# GWLB
############################################

resource "aws_lb" "gwlb" {
  name               = "${var.project_prefix}-gwlb"
  load_balancer_type = "gateway"

  # GWLB must live in subnets
  subnets = values(var.private_subnet_ids)

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

  # PAN GWLB responder uses TCP/80 by default
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

# Register firewall dataplane IPs (one per AZ)
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
  acceptance_required          = false
  gateway_load_balancer_arns   = [aws_lb.gwlb.arn]
  allowed_principals           = ["arn:aws:iam::${data.aws_caller_identity.this.account_id}:root"]

  tags = {
    Name = "${var.project_prefix}-gwlb-svc"
  }
}

############################################
# GWLBe in each private subnet (same AZs)
############################################

resource "aws_vpc_endpoint" "gwlbe" {
  for_each          = var.private_subnet_ids
  vpc_id            = var.vpc_id
  service_name      = aws_vpc_endpoint_service.gwlb_service.service_name
  vpc_endpoint_type = "GatewayLoadBalancer"
  subnet_ids        = [each.value]

  tags = {
    Name = "${var.project_prefix}-gwlbe-${each.key}"
  }
}

############################################
# Route private RTs to GWLBe (0.0.0.0/0)
############################################

resource "aws_route" "private_default_via_gwlbe" {
  for_each               = var.private_route_table_ids
  route_table_id         = each.value
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = aws_vpc_endpoint.gwlbe[each.key].id
}
