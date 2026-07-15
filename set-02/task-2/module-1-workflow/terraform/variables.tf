variable "region" {
  description = "모듈 1 리전 (과제지: ap-southeast-1)"
  type        = string
  default     = "ap-southeast-1"
}

variable "player_number" {
  description = "비번호. S3 버킷 접미사(wsc2026-student-score-bucket-<비번호>)에 사용"
  type        = string
  default     = "103"
}

variable "bucket_name_prefix" {
  description = "성적 데이터 버킷 이름 prefix. 비번호가 접미사로 붙는다 (mark 1-1)"
  type        = string
  default     = "wsc2026-student-score-bucket"
}

variable "table_name" {
  description = "성적 저장 DynamoDB 테이블 이름 (mark 1-2)"
  type        = string
  default     = "wsc2026-student-score"
}

variable "processor_function_name" {
  description = "성적 처리 Lambda 함수 이름. task.md에는 없고 mark 1-3에만 등장하는 채점 대상 이름"
  type        = string
  default     = "wsc2026-student-score-function"
}

variable "trigger_function_name" {
  description = "S3 이벤트로 워크플로우를 시작하는 트리거 Lambda 이름 (lambda.md B)"
  type        = string
  default     = "wsc2026-student-score-trigger"
}

variable "state_machine_name" {
  description = "Step Functions State Machine 이름 (mark 1-4)"
  type        = string
  default     = "wsc2026-student-score-workflow"
}

variable "lambda_role_name" {
  description = "Lambda 실행 역할 이름 (과제지 6. IAM)"
  type        = string
  default     = "wsc2026-lambda-student-role"
}

variable "sfn_role_name" {
  description = "Step Functions 실행 역할 이름 (과제지 6. IAM)"
  type        = string
  default     = "wsc2026-stepfunction-student-role"
}

variable "lambda_runtime" {
  description = "Lambda 런타임 (lambda.md: Python 3.12, mark 1-3 정확 일치)"
  type        = string
  default     = "python3.12"
}
