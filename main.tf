############################################
# cg-adv - Phase 1 Base Network (Prod-hardened)
#  - Private mgmt (no public inbound)
#  - SSM bastion with VPC endpoints
#  - VPC Flow Logs, default SG lockdown
#  - AZ discovery, provider default tags
############################################

terraform {
  required_version = ">= 1.6.0, < 2.0.0"

  cloud {
    organization = "YOUR_TFC_ORG"
    workspaces {
      name = "cg-adv-network-usw2"   # updated from usw1
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

############################################
# Provider + Default Tags
############################################
provider "aws" {
  region = "us-west-2"               # updated from us-west-1

  default_tags {
    tags = {
      Project     = "Advantus360"
      Owner       = "Isaac"
      Environment = "lab"
      CostCenter  = "CloudGenius"
    }
  }
}

############################################
# Inputs
############################################
variable "project_prefix" {
  type    = string
  default = "cg-adv"
}

variable "vpc_cidr" {
  type    = string
  default = "10.10.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid CIDR."
  }
}

variable "public_a_cidr" {
  type    = string
  default = "10.10.1.0/24"
}

variable "private_a_cidr" {
  type    = string
  default = "10.10.2.0/24"
}

variable "public_b_cidr" {
  type    = string
  default = "10.10.3.0/24"
}

variable "private_b_cidr" {
  type    = string
  default = "10.10.4.0/24"
}

# Optional: Bastion instance type (no key required for SSM)
variable "bastion_instance_type" {
  type    = string
  default = "t3.micro"
}

# Region variable used to build VPC endpoint service names
variable "region" {
  type    = string
  default = "us-west-2"              # updated from us-west-1
}

############################################
# AZ Discovery
############################################
data "aws_availability_zones" "available" {
  state = "available"
}

############################################
# VPC
############################################
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_prefix}-vpc"
  }
}

############################################
# Internet Gateway (for public subnets egress)
############################################
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project_prefix}-igw"
  }
}

############################################
# Subnets
############################################
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_a_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_prefix}-subnet-public-a"
    Tier = "public"
  }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_a_cidr
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${var.project_prefix}-subnet-private-a"
    Tier = "private"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_b_cidr
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_prefix}-subnet-public-b"
    Tier = "public"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_b_cidr
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "${var.project_prefix}-subnet-private-b"
    Tier = "private"
  }
}

############################################
# Route Tables & Associations
############################################
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project_prefix}-rt-public"
  }
}

resource "aws_route" "public_default_igw" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "assoc_public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "assoc_public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# Private RTs (default empty; later we'll add GWLB routes)
resource "aws_route_table" "private_a" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project_prefix}-rt-private-a"
  }
}

resource "aws_route_table" "private_b" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project_prefix}-rt-private-b"
  }
}

resource "aws_route_table_association" "assoc_private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private_a.id
}

resource "aws_route_table_association" "assoc_private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private_b.id
}

############################################
# Default SG lockdown (deny-by-default)
############################################
resource "aws_default_security_group" "default" {
  vpc_id                 = aws_vpc.this.id
  revoke_rules_on_delete = true
  # No ingress/egress blocks -> removes default allow rules
  tags = {
    Name = "${var.project_prefix}-default-sg-locked"
  }
}

############################################
# Security Groups
# - sg_mgmt: Palo mgmt (private) - only from bastion SG
# - sg_bastion: SSM-managed; no inbound rules required
# - sg_endpoints: for Interface Endpoints (allow 443 from VPC)
############################################
resource "aws_security_group" "sg_bastion" {
  name        = "${var.project_prefix}-sg-bastion"
  description = "SSM bastion - no inbound; egress only"
  vpc_id      = aws_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_prefix}-sg-bastion"
  }
}

resource "aws_security_group" "sg_mgmt" {
  name        = "${var.project_prefix}-sg-mgmt"
  description = "Palo Alto management - only from bastion"
  vpc_id      = aws_vpc.this.id

  # HTTPS from bastion SG
  ingress {
    description     = "Palo UI from bastion"
    protocol        = "tcp"
    from_port       = 443
    to_port         = 443
    security_groups = [aws_security_group.sg_bastion.id]
  }

  # SSH from bastion SG (fallback)
  ingress {
    description     = "SSH from bastion"
    protocol        = "tcp"
    from_port       = 22
    to_port         = 22
    security_groups = [aws_security_group.sg_bastion.id]
  }

  # Egress all for updates
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_prefix}-sg-mgmt"
  }
}

resource "aws_security_group" "sg_endpoints" {
  name        = "${var.project_prefix}-sg-endpoints"
  description = "Interface endpoint ENIs - allow HTTPS from VPC"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from VPC to endpoints"
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = [aws_vpc.this.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_prefix}-sg-endpoints"
  }
}

############################################
# VPC Endpoints (SSM without Internet)
#  - com.amazonaws.region.ssm
#  - com.amazonaws.region.ssmmessages
#  - com.amazonaws.region.ec2messages
############################################
locals {
  endpoint_subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]

  endpoint_services = [
    "ssm",
    "ssmmessages",
    "ec2messages"
  ]
}

resource "aws_vpc_endpoint" "ssm_endpoints" {
  for_each            = toset(local.endpoint_services)
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.endpoint_subnet_ids
  private_dns_enabled = true
  security_group_ids  = [aws_security_group.sg_endpoints.id]

  tags = {
    Name = "${var.project_prefix}-vpce-${each.key}"
  }
}

############################################
# SSM Bastion (private, no public IP)
############################################
# Latest Amazon Linux 2 AMI
data "aws_ami" "al2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# IAM role for SSM
resource "aws_iam_role" "bastion_role" {
  name = "${var.project_prefix}-bastion-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action   = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "${var.project_prefix}-bastion-role"
  }
}

# Attach AmazonSSMManagedInstanceCore
resource "aws_iam_role_policy_attachment" "bastion_ssm_core" {
  role       = aws_iam_role.bastion_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion_profile" {
  name = "${var.project_prefix}-bastion-profile"
  role = aws_iam_role.bastion_role.name
}

# Bastion instance (no public IP)
resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.al2.id
  instance_type               = var.bastion_instance_type
  subnet_id                   = aws_subnet.private_a.id
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.bastion_profile.name
  vpc_security_group_ids      = [aws_security_group.sg_bastion.id]

  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = "${var.project_prefix}-ssm-bastion"
  }
}

############################################
# VPC Flow Logs -> CloudWatch
############################################
resource "aws_cloudwatch_log_group" "vpc_flow" {
  name              = "/vpc/${var.project_prefix}/flow-logs"
  retention_in_days = 30
}

resource "aws_iam_role" "vpc_flow" {
  name = "${var.project_prefix}-vpc-flow-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "vpc-flow-logs.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "vpc_flow" {
  name = "${var.project_prefix}-vpc-flow-policy"
  role = aws_iam_role.vpc_flow.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ],
      Resource = "${aws_cloudwatch_log_group.vpc_flow.arn}:*"
    }]
  })
}

resource "aws_flow_log" "vpc" {
  vpc_id       = aws_vpc.this.id
  iam_role_arn = aws_iam_role.vpc_flow.arn
  traffic_type = "ALL"

  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.vpc_flow.arn

  tags = {
    Name = "${var.project_prefix}-flow-logs"
  }
}

############################################
# Outputs
############################################
output "vpc_id" {
  value = aws_vpc.this.id
}

output "subnet_ids" {
  value = {
    public_a  = aws_subnet.public_a.id
    private_a = aws_subnet.private_a.id
    public_b  = aws_subnet.public_b.id
    private_b = aws_subnet.private_b.id
  }
}

output "route_table_ids" {
  value = {
    public    = aws_route_table.public.id
    private_a = aws_route_table.private_a.id
    private_b = aws_route_table.private_b.id
  }
}

output "security_groups" {
  value = {
    mgmt      = aws_security_group.sg_mgmt.id
    bastion   = aws_security_group.sg_bastion.id
    endpoints = aws_security_group.sg_endpoints.id
  }
}

output "bastion_instance_id" {
  value = aws_instance.bastion.id
}

output "vpce_ids" {
  value = { for k, v in aws_vpc_endpoint.ssm_endpoints : k => v.id }
}
