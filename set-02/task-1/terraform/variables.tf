variable "region" {
  description = "모든 리소스를 생성할 리전 (유의사항 7)"
  type        = string
  default     = "ap-northeast-2"
}

variable "player_number" {
  description = "비번호. S3 버킷 접미사(wskorea26-concert-bucket-<비번호>)와 Grafana 계정(skills-<비번호>-admin)에 사용 (요구사항 4 / 12)"
  type        = string
  default     = "103"
}

# ----- Network (요구사항 3 / Reference01) -----

variable "vpc_name" {
  description = "VPC 이름 (Reference01)"
  type        = string
  default     = "wskorea26-vpc"
}

variable "vpc_cidr" {
  description = "VPC CIDR (Reference01)"
  type        = string
  default     = "172.16.0.0/16"
}

# Reference01: public/private 2계층 × 2 AZ(c,d)
variable "subnets" {
  description = "서브넷 정의 (Reference01)"
  type = map(object({
    cidr = string
    az   = string
    tier = string # public | private
  }))
  default = {
    "wskorea26-pub-subnet-c"  = { cidr = "172.16.1.0/24", az = "ap-northeast-2c", tier = "public" }
    "wskorea26-pub-subnet-d"  = { cidr = "172.16.2.0/24", az = "ap-northeast-2d", tier = "public" }
    "wskorea26-priv-subnet-c" = { cidr = "172.16.201.0/24", az = "ap-northeast-2c", tier = "private" }
    "wskorea26-priv-subnet-d" = { cidr = "172.16.202.0/24", az = "ap-northeast-2d", tier = "private" }
  }
}

variable "igw_name" {
  description = "인터넷 게이트웨이 이름 (Reference01)"
  type        = string
  default     = "book-igw"
}

variable "nat_name_prefix" {
  description = "NAT 게이트웨이 이름 prefix. AZ 접미사(c/d)가 붙어 book-ngw-c / book-ngw-d 가 된다 (Reference01)"
  type        = string
  default     = "book-ngw"
}

variable "public_rtb_name" {
  description = "공용 퍼블릭 라우트 테이블 이름 (Reference01)"
  type        = string
  default     = "wskorea26-public-rtb"
}

variable "private_rtb_name_prefix" {
  description = "프라이빗 라우트 테이블 이름 prefix. AZ 접미사(c/d)가 붙는다 (Reference01)"
  type        = string
  default     = "wskorea26-private-rtb"
}

variable "environment_sg_name" {
  description = "채점용 CloudShell VPC Environment 보안그룹 이름 (유의사항 13)"
  type        = string
  default     = "wskorea26-vpc-environment-sg"
}

# ----- KMS (요구사항 4 / 7 / 8) -----

variable "kms_aliases" {
  description = "용도별 CMK alias 이름"
  type = object({
    s3       = string
    dynamodb = string
    eks      = string
  })
  default = {
    s3       = "wskorea26-s3-key"
    dynamodb = "wskorea26-dynamodb-key"
    eks      = "wskorea26-eks-key"
  }
}

# ----- S3 / CloudFront (요구사항 4 / 11) -----

variable "bucket_name_prefix" {
  description = "정적 웹 버킷 이름 prefix. 비번호가 접미사로 붙는다 (요구사항 4)"
  type        = string
  default     = "wskorea26-concert-bucket"
}

variable "object_prefix" {
  description = "정적 파일 업로드 경로 (요구사항 4 Object Path)"
  type        = string
  default     = "web/main"
}

variable "cloudfront_name" {
  description = "CloudFront Distribution 이름(Comment 로 식별, mark 사전변수) (요구사항 11)"
  type        = string
  default     = "wskorea26-concert-cf"
}

variable "alb_origin_id" {
  description = "CloudFront ALB Origin ID (요구사항 11)"
  type        = string
  default     = "wskorea26-alb-origin"
}

variable "s3_origin_id" {
  description = "CloudFront S3 Origin ID (요구사항 11)"
  type        = string
  default     = "wskorea26-s3-origin"
}

variable "origin_verify_header" {
  description = "CloudFront -> ALB Origin 검증 헤더 이름 (요구사항 10 / 11)"
  type        = string
  default     = "X-Origin-Verify"
}

variable "origin_verify_value" {
  description = "CloudFront -> ALB Origin 검증 헤더 값. mark 7-2 가 이 값 그대로를 검사하므로 고정 리터럴 (요구사항 11)"
  type        = string
  default     = "wskorea26-cf"
}

variable "s3_access_header" {
  description = "CloudFront -> S3 Origin 커스텀 헤더 이름/값 (요구사항 11, mark 8-4)"
  type = object({
    name  = string
    value = string
  })
  default = {
    name  = "wskorea26-s3-access"
    value = "true"
  }
}

# ----- ECR / DynamoDB / Lambda (요구사항 6 / 7 / 9) -----

variable "ecr_repo_name" {
  description = "ECR 리포지토리 이름 (요구사항 6)"
  type        = string
  default     = "wskorea26-book-repo"
}

variable "table_name" {
  description = "DynamoDB 테이블 이름 (요구사항 7)"
  type        = string
  default     = "wskorea26-data-table"
}

variable "lambda_function_name" {
  description = "예매 조회 Lambda 함수 이름 (요구사항 9)"
  type        = string
  default     = "wskorea26-book-lambda"
}

variable "lambda_runtime" {
  description = "Lambda 런타임 (요구사항 9: Python 3.14)"
  type        = string
  default     = "python3.14"
}

# ----- EKS / ALB (요구사항 8 / 10 / 12) -----

variable "cluster_name" {
  description = "EKS 클러스터 이름 (요구사항 8)"
  type        = string
  default     = "wskorea26-cluster"
}

variable "app_namespace" {
  description = "Book 애플리케이션 네임스페이스 (요구사항 8)"
  type        = string
  default     = "wskorea26"
}

variable "book_alb_name" {
  description = "애플리케이션/Lambda 용 ALB 이름 (요구사항 10)"
  type        = string
  default     = "wskorea26-book-alb"
}

variable "grafana_alb_name" {
  description = "Grafana 접속용 ALB 이름 (요구사항 12)"
  type        = string
  default     = "wskorea26-grafana-alb"
}

variable "container_port" {
  description = "Book 앱 컨테이너 포트 (Reference02)"
  type        = number
  default     = 8080
}

variable "grafana_port" {
  description = "Grafana 파드 포트"
  type        = number
  default     = 3000
}

variable "pod_log_group_name" {
  description = "Fluent Bit 가 Pod 로그를 전송할 CloudWatch Logs 로그 그룹 (요구사항 12)"
  type        = string
  default     = "/wskorea26/eks/pod-logs"
}
