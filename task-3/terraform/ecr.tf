# 레포명 = var.apps 맵 키 = k8s 매니페스트 이미지명. 태그는 var.image_tag.
resource "aws_ecr_repository" "app" {
  for_each = local.apps

  name         = each.key
  force_delete = true
}
