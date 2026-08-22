# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

variable "addon_vpn_name" {
  description = "Client VPN 엔드포인트 Name 태그·description. VPC·SG·로그 그룹 이름도 여기서 파생. 과제지 명시 이름과 정확히 일치시킨다"
  type        = string
  default     = "skills-client-vpn"
}

# ----- VPC -----
variable "addon_vpn_vpc_cidr" {
  description = "VPC CIDR. 클라이언트 CIDR 과 겹치면 안 된다"
  type        = string
  default     = "10.70.0.0/16"
}

variable "addon_vpn_private_subnets" {
  description = "프라이빗 서브넷 (key = Name 태그). 첫 번째가 VPN 대상 네트워크·EC2 배치 서브넷. 연결(association)은 서브넷당 과금이라 기본 1개"
  type        = map(object({ cidr = string, az = string }))
  default = {
    "skills-client-vpn-private-a" = { cidr = "10.70.1.0/24", az = "ap-northeast-2a" }
  }
}

# ----- Client VPN -----
variable "addon_vpn_client_cidr" {
  description = "VPN 클라이언트에 배정할 CIDR. /22 이상 /12 이하, VPC CIDR·로컬 네트워크와 겹치지 않게"
  type        = string
  default     = "172.16.0.0/22"
}

variable "addon_vpn_server_cert_arn" {
  description = "ACM 에 import 한 서버 인증서 ARN (README 절차로 생성). 같은 리전이어야 한다"
  type        = string
}

variable "addon_vpn_client_root_cert_arn" {
  description = "클라이언트 루트 체인(CA) 인증서 ARN. 서버 인증서와 같은 CA 로 발급했으면 빈 문자열 → 서버 인증서 ARN 재사용"
  type        = string
  default     = ""
}

variable "addon_vpn_split_tunnel" {
  description = "split tunnel. true 면 VPC 대역만 터널로 가고 인터넷은 로컬. false(full tunnel)는 README 블록의 0.0.0.0/0 route·auth rule + NAT 가 추가로 필요"
  type        = bool
  default     = true
}

variable "addon_vpn_transport_protocol" {
  description = "udp(기본) 또는 tcp"
  type        = string
  default     = "udp"
}

variable "addon_vpn_log_retention_days" {
  description = "접속 로그 그룹 보존 일수"
  type        = number
  default     = 30
}

# ----- 대상 EC2 -----
variable "addon_vpn_ec2_name" {
  description = "VPN 으로 접근할 private EC2 Name 태그 (SG 이름 파생)"
  type        = string
  default     = "skills-client-vpn-target"
}

variable "addon_vpn_ec2_instance_type" {
  description = "대상 EC2 인스턴스 타입"
  type        = string
  default     = "t3.micro"
}

variable "addon_vpn_ec2_key_name" {
  description = "SSH 키 페어 이름. 빈 문자열이면 키 없이 생성 (ping·HTTP 검증만)"
  type        = string
  default     = ""
}
