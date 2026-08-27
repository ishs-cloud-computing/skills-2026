# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# ---------------------------------------------------------------------------
# Lambda Consumer 2개 + MSK 트리거 (과제지 5. Lambda — mark 3-2/3-4)
# - sensor-consumer 는 alert 토픽에 produce 하므로 VPC 내 배치 (9098 접근).
#   kafka-python + aws-msk-iam-sasl-signer 를 zip 에 번들 — 배포 전
#   `pip install -r requirements.txt -t .` 필수 (README 배포 1단계).
# - alert-consumer 는 소비 전용(ESM 이 클러스터 쪽에서 폴링) + SNS/S3 호출뿐이라
#   VPC 밖에 둔다 — NAT 경유 없이 퍼블릭 엔드포인트 직행.
# - ESM 은 IAM 인증 클러스터에서 함수 실행 역할로 자동 인증 (추가 설정 불필요)
# ---------------------------------------------------------------------------

data "archive_file" "sensor_consumer" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/sensor_consumer"
  output_path = "${path.module}/build/sensor_consumer.zip"
  excludes    = ["**/__pycache__/**"]
}

data "archive_file" "alert_consumer" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/alert_consumer"
  output_path = "${path.module}/build/alert_consumer.zip"
}

resource "aws_lambda_function" "sensor_consumer" {
  function_name    = var.consumer_fn_name
  role             = aws_iam_role.lambda.arn
  runtime          = var.lambda_runtime
  handler          = "index.handler"
  filename         = data.archive_file.sensor_consumer.output_path
  source_code_hash = data.archive_file.sensor_consumer.output_base64sha256
  timeout          = 60
  memory_size      = 256

  vpc_config {
    subnet_ids         = [for name in var.broker_subnet_names : aws_subnet.this[name].id]
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      DDB_TABLE        = aws_dynamodb_table.sensor_data.name
      ALERT_TOPIC      = var.topic_alert.name
      BOOTSTRAP_SERVER = aws_msk_cluster.this.bootstrap_brokers_sasl_iam
    }
  }

  lifecycle {
    precondition {
      condition     = fileexists("${path.module}/lambda/sensor_consumer/kafka/__init__.py")
      error_message = "kafka-python 의존성이 없습니다. 먼저 실행: pip install -r lambda/sensor_consumer/requirements.txt -t lambda/sensor_consumer/ (README 배포 1단계)"
    }
  }
}

resource "aws_lambda_function" "alert_consumer" {
  function_name    = var.alert_fn_name
  role             = aws_iam_role.lambda.arn
  runtime          = var.lambda_runtime
  handler          = "index.handler"
  filename         = data.archive_file.alert_consumer.output_path
  source_code_hash = data.archive_file.alert_consumer.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.alert.arn
      S3_BUCKET     = aws_s3_bucket.alert.id
    }
  }
}

resource "aws_lambda_event_source_mapping" "sensor" {
  event_source_arn  = aws_msk_cluster.this.arn
  function_name     = aws_lambda_function.sensor_consumer.arn
  topics            = [var.topic_raw.name]
  starting_position = "LATEST"
}

resource "aws_lambda_event_source_mapping" "alert" {
  event_source_arn  = aws_msk_cluster.this.arn
  function_name     = aws_lambda_function.alert_consumer.arn
  topics            = [var.topic_alert.name]
  starting_position = "LATEST"
}
