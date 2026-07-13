output "bucket_name" {
  description = "성적 데이터 버킷 이름 (mark2-1.sh 비번호 입력값 확인용)"
  value       = aws_s3_bucket.score.id
}

output "table_name" {
  description = "DynamoDB 테이블 이름"
  value       = aws_dynamodb_table.score.name
}

output "processor_function_name" {
  description = "성적 처리 Lambda 이름"
  value       = aws_lambda_function.processor.function_name
}

output "trigger_function_name" {
  description = "트리거 Lambda 이름"
  value       = aws_lambda_function.trigger.function_name
}

output "state_machine_arn" {
  description = "State Machine ARN (실행 확인용)"
  value       = aws_sfn_state_machine.workflow.arn
}
