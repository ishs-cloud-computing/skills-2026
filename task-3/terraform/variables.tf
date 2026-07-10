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
