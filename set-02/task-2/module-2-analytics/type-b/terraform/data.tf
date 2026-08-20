# AL2023 최신 AMI (보안 항목이라 latest 허용 — 작업 규칙 2 예외)
data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}
