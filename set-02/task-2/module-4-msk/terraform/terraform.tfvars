# 대회 당일 바뀌기 쉬운 값만 여기서 주입 (기본값은 variables.tf)
player_number = "103"

# IAM 전용 클러스터(unauthenticated=false) + 자체 IAM producer. 과제지 요구값이다.
# 제공 바이너리로 기능만 볼 때만 "tls" 로 바꾼다 — 비인증 9094 가 열려 요구 위반 상태가 된다.
producer_auth_mode = "iam"
