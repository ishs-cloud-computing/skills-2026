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
  description = "EKS NodeGroup / Karpenter 가 사용할 private 서브넷"
  value       = { for k in local.private_subnet_keys : k => aws_subnet.this[k].id }
}

output "sqs_queue_url" {
  value = aws_sqs_queue.scaling.url
}

output "sqs_queue_arn" {
  value = aws_sqs_queue.scaling.arn
}

output "keda_policy_arn" {
  value = aws_iam_policy.keda.arn
}

output "karpenter_controller_policy_arn" {
  value = aws_iam_policy.karpenter.arn
}

output "karpenter_node_role_name" {
  value = aws_iam_role.karpenter_node.name
}

output "bastion_public_ip" {
  value = aws_eip.bastion.public_ip
}
