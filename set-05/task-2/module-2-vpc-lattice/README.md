# Module 2 — VPC Lattice (ap-southeast-1)

Hub/Spoke VPC를 VPC Lattice로 연결하고, 헤더 기반 + 가중치 라우팅으로 v1/v2 애플리케이션에 분산한다. 채점은 Hub Bastion에서 수행한다(CloudShell은 Lattice DNS 접근 불가).

## 디렉토리 구조

```
module-2-vpc-lattice/
├── terraform/
│   ├── vpc.tf        # Hub(10.0/16) / Spoke(192.168/16) VPC, IGW, NAT
│   ├── bastion.tf    # wsc-hub-bastion (SSH pw Skill53##)
│   ├── app.tf        # wsc-spoke-app-v1/v2 (systemd, 8080)
│   ├── alb.tf        # Internal ALB + wsc-spoke-v{1,2}-tg + 403/404/가중 라우팅
│   └── lattice.tf    # Service Network/Service/TG(ALB)/Listener/Header Rules
└── README.md

# 앱 소스: task-2/provided/2-2/version{1,2}.py (제공 배포파일, 수정 금지) — terraform 가 직접 참조
# 채점: task-2/mark/mark2.sh (공식 채점 스크립트, Hub Bastion 에서 실행)
```

## 통신 경로

```
Hub Bastion ──(VPC Lattice)──▶ Lattice Service(wsc-app-service)
   header version=v1 ─▶ Lattice-TG wsc-spoke-v1-tg ─▶ Internal ALB:80 ─(header v1)─▶ wsc-spoke-v1-tg ─▶ app-v1
   header version=v2 ─▶ Lattice-TG wsc-spoke-v2-tg ─▶ Internal ALB:80 ─(header v2)─▶ wsc-spoke-v2-tg ─▶ app-v2
   header 없음        ─▶ Default Rule(99999) v1:90/v2:10
```

직접 VPC Peering·Private IP 접근 없이 모든 Hub→Spoke 트래픽은 Lattice를 경유한다.

## 배포 순서

```bash
cd terraform
terraform init && terraform apply -auto-approve

# 산출물 확인
terraform output lattice_service_dns
terraform output bastion_public_ip

# Hub Bastion 으로 SSH(비밀번호 Skill53##) 접속 후 셀프 채점
#   ssh ec2-user@$(terraform output -raw bastion_public_ip)
#   aws configure set default.region ap-southeast-1
bash ../../mark/mark2.sh
```

## 요구사항 ↔ 구현 매핑 (채점지 2)

| 항목 | 요구사항 | 구현 |
|------|----------|------|
| 2-1 | 인프라(Hub/Spoke VPC, Bastion, App) | `vpc.tf`, `bastion.tf`, `app.tf` |
| 2-2 | Internal ALB + v1/v2 TG (HTTP 8080) | `alb.tf` |
| 2-3 | Lattice SN/Service + hub·spoke VPC 연결 | `lattice.tf` |
| 2-4 | Default Rule 가중 (v1:90/v2:10) | `lattice.tf` listener default_action |
| 2-5 | Header Rule (v1→p10, v2→p20, weight 100) | `lattice.tf` listener_rule v1/v2 |
| 2-6 | TG health + curl 버전 응답 | `app/version{1,2}.py` + ALB/Lattice |

## 주의 / 검증 포인트

- **이름 정확 일치**: SN `wsc-app-service-network`, Service `wsc-app-service`, ALB `wsc-spoke-app-alb`, TG `wsc-spoke-v1-tg`/`wsc-spoke-v2-tg`(ELBv2·Lattice 양쪽 동일 이름).
- Lattice TG는 `type=ALB`로 Internal ALB:80을 대상으로 한다. ALB SG는 VPC Lattice 관리형 prefix list(`com.amazonaws.ap-southeast-1.vpc-lattice`)에서 80 inbound를 허용한다.
- 헤더 라우팅 우선순위: Lattice Header Rule(priority 10/20)이 Default Rule(99999, 가중)보다 우선 평가된다.
- App은 제공 Flask 앱(`provided/2-2/`)이므로 user_data가 private subnet(NAT)에서 `pip install flask` 후 systemd로 8080 실행한다. 제공 파일은 수정하지 않는다.
- `version: v1/v2` 헤더는 Lattice→ALB로 보존되어 ALB도 동일 헤더 규칙으로 최종 App을 선택한다.
