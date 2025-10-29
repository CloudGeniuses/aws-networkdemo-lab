############################################
# NAT Gateway (public-a) + Private RT Routes
############################################

# Elastic IP for NAT Gateway
resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = {
    Name = "${var.project_prefix}-nat-eip"
  }
}

# NAT Gateway deployed in public-a subnet
resource "aws_nat_gateway" "nat" {
  subnet_id     = aws_subnet.public_a.id          # cg-adv-subnet-public-a
  allocation_id = aws_eip.nat_eip.id

  tags = {
    Name = "${var.project_prefix}-natgw-a"
  }

  depends_on = [
    aws_internet_gateway.igw
  ]
}

# Collect private route tables
locals {
  private_route_tables = {
    private_a = aws_route_table.private_a.id
    private_b = aws_route_table.private_b.id
  }
}

# Add 0.0.0.0/0 route to NAT Gateway in each private RT
resource "aws_route" "private_default_via_nat" {
  for_each = local.private_route_tables

  route_table_id         = each.value
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}
