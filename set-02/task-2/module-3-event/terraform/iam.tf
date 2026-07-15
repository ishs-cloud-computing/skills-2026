# ---------------------------------------------------------------------------
# IAM — Lambda 공용 실행 역할 (과제지 6. Lambda, 최소권한)
# - 6개 함수가 하나의 역할 공유 (과제지가 역할 이름을 단수로 지정)
# - EC2 변조 액션은 인스턴스/SG ARN 으로 스코프, Describe 는 리소스 레벨 미지원이라 *
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

resource "aws_iam_role" "lambda" {
  name               = var.lambda_role_name
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "lambda_remediation" {
  statement {
    sid = "DescribeEc2"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeIamInstanceProfileAssociations",
    ]
    resources = ["*"]
  }

  statement {
    sid     = "RevokeSgIngress"
    actions = ["ec2:RevokeSecurityGroupIngress"]
    resources = [
      "arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:security-group/${aws_security_group.event.id}"
    ]
  }

  statement {
    sid = "RemediateInstance"
    actions = [
      "ec2:StartInstances",
      "ec2:StopInstances",
      "ec2:ModifyInstanceAttribute",
      "ec2:AssociateIamInstanceProfile",
      "ec2:ReplaceIamInstanceProfileAssociation",
    ]
    resources = [
      "arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:instance/${aws_instance.event.id}"
    ]
  }

  statement {
    sid       = "PassEc2Role"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.ec2.arn]
  }

  statement {
    sid       = "PublishAlert"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alert.arn]
  }
}

resource "aws_iam_role_policy" "lambda_remediation" {
  name   = "${var.lambda_role_name}-remediation"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_remediation.json
}
