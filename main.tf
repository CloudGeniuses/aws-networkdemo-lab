############################################
# PHASE 0 — Global Conventions (use everywhere)
############################################

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-west-1"
}

locals {
  region         = "us-west-1"
  azs            = ["us-west-1a", "us-west-1b"]
  project_prefix = "cg-adv"

  common_tags = {
    Project     = "Advantus360"
    Owner       = "Isaac"
    Environment = "lab"
    CostCenter  = "CloudGenius"
  }
}

variable "admin_ip" {
  description = "Trusted admin IP for management access (e.g. 203.0.113.10/32)"
  type        = string
}


############################################
# PHASE 1 — Base Network (manual)
############################################

### 1.1 VPC ###
resource "aws_vpc" "main" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "${local.project_prefix}-vpc"
  })
}


### 1.2 Subnets ###
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.10.1.0/24"
  availability_zone       = local.azs[0]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name    = "${local.project_prefix}-subnet-public-a"
    Purpose = "FW#1 mgmt + untrust"
  })
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.10.2.0/24"
  availability_zone = local.azs[0]

  tags = merge(local.common_tags, {
    Name    = "${local.project_prefix}-subnet-private-a"
    Purpose = "FW#1 trust (+ HA2 point-to-point /30)"
  })
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.10.3.0/24"
  availability_zone       = local.azs[1]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name    = "${local.project_prefix}-subnet-public-b"
    Purpose = "FW#2 mgmt + untrust"
  })
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.10.4.0/24"
  availability_zone = local.azs[1]

  tags = merge(local.common_tags, {
    Name    = "${local.project_prefix}-subnet-private-b"
    Purpose = "FW#2 trust"
  })
}


### 1.3 Internet Gateway & Route Tables ###
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.project_prefix}-igw"
  })
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_prefix}-rt-public"
  })
}

# Associate Public Subnets
resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# Private Route Tables (empty for now)
resource "aws_route_table" "private_a" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.project_prefix}-rt-private-a"
  })
}

resource "aws_route_table" "private_b" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.project_prefix}-rt-private-b"
  })
}


### 1.4 Security Group (management + SSH fallback) ###
resource "aws_security_group" "mgmt" {
  name        = "${local.project_prefix}-sg-mgmt"
  description = "Management + fallback SSH access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS (Palo Alto UI)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip]
  }

  ingress {
    description = "SSH fallback"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_prefix}-sg-mgmt"
  })
}
