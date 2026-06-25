# 대회에서 바뀌기 쉬운 값은 여기서 주입한다 (CLAUDE.md 변수 규칙).
# 값은 variables.tf default 와 동일 — 대회 당일 이름/CIDR/AZ 변경 시 이 파일만 수정한다.
region                = "ap-northeast-2"
cluster_name          = "wsc-scaling-cluster"
vpc_cidr              = "10.11.0.0/16"
bastion_instance_type = "t3.medium"
sqs_name              = "wsc-scaling-sqs"
ssh_password          = "Skill53##"

# 과제지 "VPC 구성" 표와 정확히 일치 (이름 일치 채점).
subnets = {
  "wsc-scaling-sn-pub-a"  = { cidr = "10.11.0.0/24", az = "ap-northeast-2a", tier = "public" }
  "wsc-scaling-sn-pub-c"  = { cidr = "10.11.1.0/24", az = "ap-northeast-2c", tier = "public" }
  "wsc-scaling-sn-priv-a" = { cidr = "10.11.10.0/24", az = "ap-northeast-2a", tier = "private" }
  "wsc-scaling-sn-priv-c" = { cidr = "10.11.11.0/24", az = "ap-northeast-2c", tier = "private" }
}
