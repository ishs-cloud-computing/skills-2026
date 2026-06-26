data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  # 요구사항 10: S3 버킷 gj2026-static-<비번호>
  bucket_name = "gj2026-static-${var.seat_number}"

  subnet_keys = keys(var.subnets)
  subnet_ids  = [for k in local.subnet_keys : aws_subnet.this[k].id]

  # AZ 접미사(a/b) → 서브넷 키 매핑 (가용영역별 리소스 배치에 사용)
  subnet_by_az = { for k, v in var.subnets : v.az => k }
}
