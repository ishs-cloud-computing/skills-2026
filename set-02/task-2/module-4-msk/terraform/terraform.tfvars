# 대회 당일 바뀌기 쉬운 값만 여기서 주입 (기본값은 variables.tf)
player_number = "103"

# 정통 경로(기본): IAM 전용 클러스터(unauthenticated=false) + 자체 IAM producer 9098.
# 과제지 "IAM 인증을 통해서만 접근" 요구를 실제로 만족하는 구성이다.
# 대회 당일 제출은 제공 바이너리만 배포 가능하므로 우회 경로를 -var 로 지정한다:
#   terraform apply -var "producer_auth_mode=tls"
producer_auth_mode = "iam"
