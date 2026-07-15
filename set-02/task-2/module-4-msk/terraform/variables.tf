variable "region" {
  description = "모듈 4 리전 (과제지: ap-northeast-1)"
  type        = string
  default     = "ap-northeast-1"
}

variable "player_number" {
  description = "비번호 (mark 4-1 버킷 이름 접미사: wsc2026-sensor-alert-bucket-<비번호>)"
  type        = string
  default     = "103"
}

# ----- Network (과제지 1. VPC) -----

variable "vpc_name" {
  description = "VPC 이름"
  type        = string
  default     = "msk-vpc"
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "192.168.0.0/16"
}

# 과제지 표대로 AZ 는 a/d (ap-northeast-1 은 신규 계정에서 1b 사용 불가 — a/c/d 만 존재)
variable "subnets" {
  description = "서브넷 정의 (과제지 표와 Name 태그 정확 일치)"
  type = map(object({
    cidr = string
    az   = string
    tier = string # public | private
  }))
  default = {
    "msk-pub-a"  = { cidr = "192.168.0.0/24", az = "ap-northeast-1a", tier = "public" }
    "msk-pub-d"  = { cidr = "192.168.1.0/24", az = "ap-northeast-1d", tier = "public" }
    "msk-priv-a" = { cidr = "192.168.10.0/24", az = "ap-northeast-1a", tier = "private" }
    "msk-priv-d" = { cidr = "192.168.11.0/24", az = "ap-northeast-1d", tier = "private" }
  }
}

variable "igw_name" {
  description = "인터넷 게이트웨이 이름"
  type        = string
  default     = "msk-igw"
}

variable "nat_name" {
  description = "NAT 게이트웨이 이름 (단일 NAT, msk-pub-a 배치, 두 프라이빗 RTB 공유)"
  type        = string
  default     = "msk-ngw"
}

variable "nat_subnet_name" {
  description = "NAT 게이트웨이를 배치할 퍼블릭 서브넷 이름"
  type        = string
  default     = "msk-pub-a"
}

variable "pub_rtb_name" {
  description = "퍼블릭 라우트 테이블 이름 (두 퍼블릭 서브넷 공용)"
  type        = string
  default     = "msk-pub-rtb"
}

variable "priv_rtb_names" {
  description = "프라이빗 서브넷별 라우트 테이블 이름 (key = 서브넷 이름)"
  type        = map(string)
  default = {
    "msk-priv-a" = "msk-priv-a-rtb"
    "msk-priv-d" = "msk-priv-d-rtb"
  }
}

# ----- MSK (과제지 2. MSK, 3. MSK Topic — mark 4-3) -----

variable "cluster_name" {
  description = "MSK 클러스터 이름 (mark 4-3 정확 일치)"
  type        = string
  default     = "wsc2026-msk-cluster"
}

variable "kafka_version" {
  description = "Kafka 버전 (mark 4-3: 3.6.0)"
  type        = string
  default     = "3.6.0"
}

variable "broker_instance_type" {
  description = "브로커 인스턴스 타입 (mark 4-3: kafka.t3.small)"
  type        = string
  default     = "kafka.t3.small"
}

variable "broker_subnet_names" {
  description = "브로커 배치 프라이빗 서브넷 (고가용성 2AZ — RF 2 를 지지하는 최소 구성)"
  type        = list(string)
  default     = ["msk-priv-a", "msk-priv-d"]
}

variable "broker_volume_size" {
  description = "브로커 EBS 크기(GiB) — 센서 스트림에는 최소로 충분"
  type        = number
  default     = 10
}

variable "topic_raw" {
  description = "원시 센서 토픽 (과제지 3. MSK Topic 표)"
  type = object({
    name               = string
    partitions         = number
    replication_factor = number
  })
  default = {
    name               = "wsc2026-sensor-raw"
    partitions         = 3
    replication_factor = 2
  }
}

variable "topic_alert" {
  description = "이상치 토픽 (과제지 3. MSK Topic 표)"
  type = object({
    name               = string
    partitions         = number
    replication_factor = number
  })
  default = {
    name               = "wsc2026-sensor-alert"
    partitions         = 1
    replication_factor = 2
  }
}

# ----- EC2 Producer (과제지 4. EC2, provided/module4/Application.md) -----

variable "producer_name" {
  description = "Producer EC2 이름 태그"
  type        = string
  default     = "wsc2026-sensor-producer"
}

variable "producer_type" {
  description = "Producer EC2 인스턴스 타입"
  type        = string
  default     = "t3.small"
}

variable "producer_subnet_name" {
  description = "Producer 배치 프라이빗 서브넷"
  type        = string
  default     = "msk-priv-a"
}

variable "ec2_role_name" {
  description = "Producer EC2 IAM 역할 이름 (과제지 4. EC2, 최소권한)"
  type        = string
  default     = "wsc2026-msk-ec2-role"
}

variable "msk_iam_auth_version" {
  description = "kafka CLI 용 aws-msk-iam-auth uber jar 버전 (토픽 생성·디버깅)"
  type        = string
  default     = "2.3.7"
}

# producer 인증 경로 스위치. tls(기본): 제공 바이너리 + 비인증 TLS 9094 (채점 검증 완료 경로).
# iam: 자체 구현한 IAM 인증 바이너리 + SASL/IAM 9098, 클러스터는 IAM 전용(unauthenticated=false)
# 으로 좁혀 과제지 "IAM 인증을 통해서만 접근" 요구를 실제로 만족한다.
variable "producer_auth_mode" {
  description = "producer 접속 방식: tls(제공 바이너리·9094) 또는 iam(자체 바이너리·9098)"
  type        = string
  default     = "tls"
  validation {
    condition     = contains(["tls", "iam"], var.producer_auth_mode)
    error_message = "producer_auth_mode 는 tls 또는 iam 이어야 한다."
  }
}

# producer_auth_mode="iam" 일 때 S3 로 올릴 자체 IAM 바이너리 경로 (placeholder — 빌드한 바이너리를 이 경로에 둔다).
variable "iam_producer_binary_path" {
  description = "IAM 인증 producer 바이너리 경로 (auth_mode=iam 에서만 사용)"
  type        = string
  default     = "../app/producer"
}

# ----- Lambda Consumer (과제지 5. Lambda, provided/module4/lambda.md — mark 4-2/4-4) -----

variable "lambda_role_name" {
  description = "Lambda 공용 실행 역할 이름 (과제지 5. Lambda, 최소권한)"
  type        = string
  default     = "wsc2026-msk-lambda-role"
}

variable "lambda_runtime" {
  description = "Lambda 런타임 (mark 4-2 가 python3.14 정확 일치 채점)"
  type        = string
  default     = "python3.14"
}

variable "consumer_fn_name" {
  description = "raw 토픽 소비 Lambda 이름 (mark 4-2)"
  type        = string
  default     = "wsc2026-sensor-consumer"
}

variable "alert_fn_name" {
  description = "alert 토픽 소비 Lambda 이름 (mark 4-2)"
  type        = string
  default     = "wsc2026-sensor-alert-consumer"
}

# ----- DynamoDB / S3 / SNS (과제지 6. DynamoDB, 7. S3 — mark 4-1) -----

variable "table_name" {
  description = "센서 데이터 테이블 이름 (mark 4-1: PK sensorId, SK timestamp)"
  type        = string
  default     = "wsc2026-sensor-data"
}

variable "bucket_prefix" {
  description = "오류 데이터 버킷 이름 접두사 (mark 4-1 이 <prefix>-<비번호> 로 head-bucket)"
  type        = string
  default     = "wsc2026-sensor-alert-bucket"
}

variable "sns_topic_name" {
  description = "alert consumer 가 발행할 SNS Topic 이름 (채점 항목 아님 — lambda.md SNS_TOPIC_ARN 용)"
  type        = string
  default     = "wsc2026-sensor-alert-topic"
}

# ----- Bastion (유의사항 10: 채점용 Bastion — kafka 디버깅 겸용) -----

variable "bastion_instance_type" {
  description = "Bastion 인스턴스 타입"
  type        = string
  default     = "t3.micro"
}

variable "ssh_password" {
  description = "Bastion ec2-user SSH 패스워드"
  type        = string
  default     = "Skill53##"
  sensitive   = true
}
