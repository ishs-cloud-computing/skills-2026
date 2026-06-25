output "account_id" {
  value = local.account_id
}

output "region" {
  value = var.region
}

output "vpc_id" {
  value = aws_vpc.this.id
}

output "private_subnet_ids" {
  value = { for k in local.private_subnet_keys : k => aws_subnet.this[k].id }
}

output "public_subnet_ids" {
  value = { for k in local.public_subnet_keys : k => aws_subnet.this[k].id }
}

output "app_public_ip" {
  value = aws_instance.app.public_ip
}
