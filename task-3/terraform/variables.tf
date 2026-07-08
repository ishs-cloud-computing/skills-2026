# 실행별 입력만 변수로 둔다. 과제 상수(이름·CIDR·앱 목록·DB 사양)는 locals.tf.
variable "player_number" {
  description = "대회 비번호"
  type        = string
}

variable "db_password" {
  description = "RDS master 비밀번호"
  type        = string
  sensitive   = true
  default     = "password"
}

# ── WAF: requestid/uuid 쿼리스트링 누락 차단 룰 토글.
# 기본 count — 당일 실트래픽의 쿼리스트링을 관찰한 뒤 -var waf_v1_block_enabled=true로 활성.
variable "waf_v1_block_enabled" {
  type    = bool
  default = false
}
