output "account_id" {
  value = local.account_id
}

output "hub_vpc_id" {
  value = aws_vpc.hub.id
}

output "spoke_vpc_id" {
  value = aws_vpc.spoke.id
}

output "bastion_public_ip" {
  value = aws_eip.bastion.public_ip
}

output "alb_dns_name" {
  value = aws_lb.app.dns_name
}

output "lattice_service_dns" {
  description = "Hub Bastion 에서 curl 대상이 되는 Lattice 서비스 DNS"
  value       = aws_vpclattice_service.this.dns_entry[0].domain_name
}
