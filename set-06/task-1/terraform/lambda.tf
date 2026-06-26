# ---------------------------------------------------------------------------
# Lambda (요구사항 11)
# - Name: gj2026-book-reservation / Runtime: python3.14
# - Private Subnet 내 운용(VPC 연결), DynamoDB 조회(표준 엔드포인트→VPCe)
# - Function URL 을 CloudFront /reservation* origin 으로 사용 (cloudfront.tf)
# - GET /reservation        -> 전체 Scan
# - GET /reservation?client_id=Cxxx -> GSI(client_id-index) Query
# - 호출 시 client_id 별 CloudWatch 메트릭 적재(요구사항 14)
# ---------------------------------------------------------------------------

data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/build/lambda.zip"
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

resource "aws_iam_role" "lambda" {
  name               = "gj2026-book-reservation-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "lambda_perms" {
  statement {
    sid       = "DynamoRead"
    actions   = ["dynamodb:GetItem", "dynamodb:Query", "dynamodb:Scan"]
    resources = [aws_dynamodb_table.books.arn, "${aws_dynamodb_table.books.arn}/index/*"]
  }
  statement {
    sid       = "KmsDecrypt"
    actions   = ["kms:Decrypt", "kms:DescribeKey"]
    resources = [aws_kms_key.dynamodb.arn]
  }
  statement {
    sid       = "PutMetric"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]
  }
  statement {
    sid = "VpcEni"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DeleteNetworkInterface",
    ]
    resources = ["*"]
  }
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${var.region}:${local.account_id}:*"]
  }
}

resource "aws_iam_role_policy" "lambda" {
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_perms.json
}

resource "aws_security_group" "lambda" {
  name        = "gj2026-lambda-sg"
  description = "Lambda ENI SG"
  vpc_id      = aws_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "gj2026-lambda-sg" }
}

resource "aws_lambda_function" "reservation" {
  function_name    = "gj2026-book-reservation"
  role             = aws_iam_role.lambda.arn
  runtime          = var.lambda_runtime
  handler          = "index.handler"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 15

  environment {
    variables = {
      TABLE_NAME       = aws_dynamodb_table.books.name
      GSI_NAME         = "client_id-index"
      METRIC_NAMESPACE = "gj2026/Reservation"
    }
  }

  vpc_config {
    subnet_ids         = local.subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  tags = { Name = "gj2026-book-reservation" }
}

# Function URL → CloudFront custom origin. WAF(CloudFront scope)가 client_id 정규식을
# 검사하므로 Function URL 자체는 인증 없이(NONE) 노출하되 CloudFront 경유로만 사용.
resource "aws_lambda_function_url" "reservation" {
  function_name      = aws_lambda_function.reservation.function_name
  authorization_type = "NONE"
}
