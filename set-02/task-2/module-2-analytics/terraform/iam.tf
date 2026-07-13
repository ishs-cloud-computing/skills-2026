# ---------------------------------------------------------------------------
# IAM — 애플리케이션 EC2 역할 (과제지 6. IAM, 최소권한)
# - 역할 이름 wsc2026-alaytics-ec2-role 은 과제지 원문 오타(alaytics)를
#   의도적으로 유지한 것. 이름 정확 일치 채점 대비이므로 고치지 말 것.
# - SSM 접근 필수 (과제지 2. EC2 "채점시 SSM 사용", mark 2-6 send-command)
# - 앱은 kinesis put_record 만 호출 (provided/module2/app.py)
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

resource "aws_iam_role" "app" {
  name               = var.ec2_role_name
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "app_ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "app_kinesis" {
  statement {
    sid       = "PutOrderRecords"
    effect    = "Allow"
    actions   = ["kinesis:PutRecord"]
    resources = [aws_kinesis_stream.orders.arn]
  }
}

resource "aws_iam_role_policy" "app_kinesis" {
  name   = "${var.ec2_role_name}-kinesis"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.app_kinesis.json
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.ec2_role_name}-profile"
  role = aws_iam_role.app.name
}
