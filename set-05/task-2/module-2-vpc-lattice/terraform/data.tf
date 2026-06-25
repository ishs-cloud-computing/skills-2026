data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# VPC Lattice 가 대상(ALB)으로 인입할 때 사용하는 관리형 prefix list.
# ALB Security Group inbound 허용에 사용한다.
data "aws_ec2_managed_prefix_list" "lattice" {
  name = "com.amazonaws.${var.region}.vpc-lattice"
}

locals {
  account_id = data.aws_caller_identity.current.account_id

  vpc_ids = {
    hub   = aws_vpc.hub.id
    spoke = aws_vpc.spoke.id
  }

  hub_public_keys    = [for k, v in var.subnets : k if v.vpc == "hub" && v.tier == "public"]
  spoke_public_keys  = [for k, v in var.subnets : k if v.vpc == "spoke" && v.tier == "public"]
  spoke_private_keys = [for k, v in var.subnets : k if v.vpc == "spoke" && v.tier == "private"]

  # NAT 배치를 위한 spoke public AZ 매핑
  spoke_public_by_az = { for k in local.spoke_public_keys : var.subnets[k].az => k }
}
