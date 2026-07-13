resource "aws_ecr_repository" "app" {
  for_each = local.apps

  name         = each.key
  force_delete = true
}
