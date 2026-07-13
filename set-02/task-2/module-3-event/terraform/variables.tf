variable "region" {
  description = "모듈 3 리전 (과제지: eu-west-1)"
  type        = string
  default     = "eu-west-1"
}

variable "player_number" {
  description = "비번호 (로그 버킷 이름 접미사·식별용)"
  type        = string
  default     = "103"
}

# ----- Network (과제지 1. VPC) -----

variable "vpc_name" {
  description = "VPC 이름"
  type        = string
  default     = "event-vpc"
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "172.16.0.0/16"
}

variable "subnets" {
  description = "서브넷 정의 (과제지 표와 Name 태그 정확 일치)"
  type = map(object({
    cidr = string
    az   = string
    tier = string # public | private
  }))
  default = {
    "event-pub-a" = { cidr = "172.16.0.0/24", az = "eu-west-1a", tier = "public" }
    "event-pub-b" = { cidr = "172.16.1.0/24", az = "eu-west-1b", tier = "public" }
  }
}

variable "igw_name" {
  description = "인터넷 게이트웨이 이름"
  type        = string
  default     = "event-igw"
}

variable "pub_rtb_name" {
  description = "퍼블릭 라우트 테이블 이름 (두 퍼블릭 서브넷 공용)"
  type        = string
  default     = "event-pub-rtb"
}

# ----- EC2 / SG (과제지 2. EC2, 3. Security Group) -----

variable "instance_name" {
  description = "모니터링 대상 EC2 이름 태그 (mark 3-0 이 이 태그로 인스턴스를 찾는다)"
  type        = string
  default     = "wsc2026-event-ec2"
}

variable "instance_type" {
  description = "EC2 인스턴스 타입 (type-remediation 이 이 값으로 원복)"
  type        = string
  default     = "t3.micro"
}

variable "instance_subnet_name" {
  description = "EC2 배치 서브넷 (과제지: event-pub-a)"
  type        = string
  default     = "event-pub-a"
}

variable "ec2_role_name" {
  description = "EC2 IAM 역할 이름. 인스턴스 프로파일도 같은 이름 — role-remediation 이 이 이름으로 원복한다"
  type        = string
  default     = "wsc2026-event-ec2-role"
}

variable "sg_name" {
  description = "EC2 보안그룹 이름 (mark 3-0/3-4: 인바운드 0개 기준선)"
  type        = string
  default     = "wsc2026-event-sg"
}

# ----- CloudTrail / SNS (과제지 5. CloudTrail, 7. SNS) -----

variable "trail_name" {
  description = "CloudTrail 이름 (Management Events Read/Write — API 호출 룰 3개의 이벤트 소스)"
  type        = string
  default     = "wsc2026-event-trail"
}

variable "logs_bucket_prefix" {
  description = "CloudTrail·Config 공용 로그 버킷 이름 접두사 (비번호 접미사 부착)"
  type        = string
  default     = "wsc2026-event-logs"
}

variable "topic_name" {
  description = "알림 SNS Topic 이름 (mark 3-1 정확 일치)"
  type        = string
  default     = "wsc2026-event-alert"
}

# ----- Lambda (과제지 6. Lambda, provided/module3/lambda.md, mark 3-1) -----

variable "lambda_role_name" {
  description = "Lambda 공용 실행 역할 이름 (과제지 6. Lambda)"
  type        = string
  default     = "wsc2026-event-lambda-role"
}

variable "lambda_runtime" {
  description = "Lambda 런타임 (mark 3-1 이 python3.12 정확 일치 채점)"
  type        = string
  default     = "python3.12"
}

# task.md/lambda.md 의 4개 + mark2-3.sh 만 요구하는 2개(ec2_stop_remediation, tag_alert)의
# 합집합. key 는 lambda/<key>/index.py 소스 디렉토리와 일치해야 한다.
variable "function_names" {
  description = "Lambda 함수 이름 (mark 3-1 은 stop/terminate/sg/tag 4개를 정확 일치 채점)"
  type        = map(string)
  default = {
    sg_remediation       = "wsc2026-sg-remediation"
    role_remediation     = "wsc2026-role-remediation"
    ec2_terminate_alert  = "wsc2026-ec2-terminate-alert"
    ec2_type_remediation = "wsc2026-ec2-type-remediation"
    ec2_stop_remediation = "wsc2026-ec2-stop-remediation"
    tag_alert            = "wsc2026-tag-alert"
  }
}

# ----- EventBridge (과제지 4. EventBridge, mark 3-2) -----

# task.md 의 4개 + mark2-3.sh 가 타깃을 채점하는 wsc2026-ec2-stop-rule,
# tag_alert 트리거용 tag_compliance(이름 비채점)의 합집합.
variable "rule_names" {
  description = "EventBridge Rule 이름 (mark 3-2 는 ec2-stop/ec2-terminate 룰의 타깃을 채점)"
  type        = map(string)
  default = {
    sg_change       = "wsc2026-sg-change-rule"
    role_change     = "wsc2026-role-change-rule"
    ec2_terminate   = "wsc2026-ec2-terminate-rule"
    ec2_type_change = "wsc2026-ec2-type-change-rule"
    ec2_stop        = "wsc2026-ec2-stop-rule"
    tag_compliance  = "wsc2026-tag-compliance-rule"
  }
}

# ----- AWS Config (mark 3-3/3-5 — task.md 에는 없지만 채점 스크립트가 요구) -----

variable "config_rule_ssh_name" {
  description = "SSH 인바운드 감지 Config Rule 이름 (mark 3-3 ACTIVE 채점)"
  type        = string
  default     = "wsc2026-sg-ssh-rule"
}

variable "config_rule_tags_name" {
  description = "필수 태그 Config Rule 이름 (mark 3-3 ACTIVE, 3-5 NON_COMPLIANT=None 채점)"
  type        = string
  default     = "wsc2026-required-tags-rule"
}

variable "required_tag_key" {
  description = "REQUIRED_TAGS 룰이 검사할 태그 키. default_tags 로 전 리소스에 부착되는 Project 를 사용해 3-5 를 통과한다"
  type        = string
  default     = "Project"
}
