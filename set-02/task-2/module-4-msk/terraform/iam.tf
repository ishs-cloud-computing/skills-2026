# ---------------------------------------------------------------------------
# IAM (과제지 4. EC2 / 5. Lambda — 최소권한)
# - EC2: 토픽 생성(CreateTopic) + raw 토픽 produce + S3 바이너리 다운로드 + SSM
# - Lambda: 두 함수가 하나의 역할 공유 (과제지가 역할 이름을 단수로 지정)
#   ESM 폴러(managed AWSLambdaMSKExecutionRole) + kafka-cluster 데이터 액션
#   + DynamoDB put / SNS publish / S3 put
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# ----- Producer EC2 -----

resource "aws_iam_role" "producer" {
  name               = var.ec2_role_name
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "producer_ssm" {
  role       = aws_iam_role.producer.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "producer" {
  statement {
    sid       = "ConnectCluster"
    actions   = ["kafka-cluster:Connect", "kafka-cluster:DescribeCluster", "kafka-cluster:WriteDataIdempotently"]
    resources = [aws_msk_cluster.this.arn]
  }

  statement {
    sid       = "ManageAndProduceTopics"
    actions   = ["kafka-cluster:CreateTopic", "kafka-cluster:DescribeTopic", "kafka-cluster:WriteData"]
    resources = [local.raw_topic_arn, local.alert_topic_arn]
  }

  statement {
    sid       = "DownloadAppBinary"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.alert.arn}/bin/*"]
  }
}

resource "aws_iam_role_policy" "producer" {
  name   = "${var.ec2_role_name}-msk"
  role   = aws_iam_role.producer.id
  policy = data.aws_iam_policy_document.producer.json
}

resource "aws_iam_instance_profile" "producer" {
  name = "${var.ec2_role_name}-profile"
  role = aws_iam_role.producer.name
}

# ----- Lambda Consumer 공용 역할 -----

resource "aws_iam_role" "lambda" {
  name               = var.lambda_role_name
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# ESM 폴러 권한: kafka:DescribeCluster*/GetBootstrapBrokers + ENI 관리 + logs
resource "aws_iam_role_policy_attachment" "lambda_msk_esm" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaMSKExecutionRole"
}

data "aws_iam_policy_document" "lambda" {
  statement {
    sid = "ConnectCluster"
    # WriteDataIdempotently: kafka-python 3.x KafkaProducer 는 기본이 멱등 프로듀서라
    # alert 토픽 발행 시 InitProducerId(클러스터 레벨)를 호출한다 — 없으면 Error 31.
    actions   = ["kafka-cluster:Connect", "kafka-cluster:DescribeCluster", "kafka-cluster:WriteDataIdempotently"]
    resources = [aws_msk_cluster.this.arn]
  }

  statement {
    sid       = "ConsumeTopics"
    actions   = ["kafka-cluster:DescribeTopic", "kafka-cluster:ReadData"]
    resources = [local.raw_topic_arn, local.alert_topic_arn]
  }

  statement {
    sid       = "ProduceAlertTopic"
    actions   = ["kafka-cluster:WriteData"]
    resources = [local.alert_topic_arn]
  }

  statement {
    sid       = "ConsumerGroups"
    actions   = ["kafka-cluster:DescribeGroup", "kafka-cluster:AlterGroup"]
    resources = [local.any_group_arn]
  }

  statement {
    sid       = "StoreSensorData"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.sensor_data.arn]
  }

  statement {
    sid       = "PublishAlert"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alert.arn]
  }

  statement {
    sid       = "SaveAlertLog"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.alert.arn}/alert/*"]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "${var.lambda_role_name}-data"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda.json
}
