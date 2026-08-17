# 대회 당일 바뀌기 쉬운 값만 여기서 주입 (기본값은 variables.tf)
player_number = "103"

# 대회 당일 쓸 값은 module-4-msk/select-auth-mode.ps1 판정을 따른다 — 그날 제공 바이너리가
# IAM 인증을 못 하면 terraform apply -var "producer_auth_mode=tls" 로 내려간다.
# (두 경로 비교는 README.md "producer 인증 경로" 절)
producer_auth_mode = "iam"
