variable "project_prefix" {
  description = "Prefix for all GWLB resources (e.g., acme-prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where GWLB and endpoints will be deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "Map of private subnet IDs for GWLBe placement; keys should match route table map (e.g., a, b)"
  type        = map(string)
}

variable "private_route_table_ids" {
  description = "Map of private route table IDs; keys must match private_subnet_ids"
  type        = map(string)
}

variable "fw_endpoints" {
  description = <<EOT
List of firewall dataplane IPs with their AZ for GWLB target attachments.
Example:
[
  { ip = "10.10.2.50", az = "us-west-2a" },
  { ip = "10.10.4.50", az = "us-west-2b" }
]
EOT

  type = list(
    object(
      {
        ip = string
        az = string
      }
    )
  )

  default = []
}
