# keycloak 부착 스니펫

2과제 카탈로그 모듈 10 "Keycloak (VPC, EC2, IAM, Keycloak)" 스타터 키트. 저장소에 실전 구현이 없는
모듈이라 **자족적인 terraform 모듈**(VPC 포함)로 만들었다 — 당일 모듈 5·6 으로 출제되면
`_template/task-2/module-4` 복사본의 `terraform/` 에 통째로 넣고 시작한다.

구성: VPC(퍼블릭 2 AZ) · EC2 AL2023 `t3.small` + docker 로 `quay.io/keycloak/keycloak` 기동 ·
ALB HTTP 80 → 8080 · SG 체인 · IAM 인스턴스 프로파일(SSM + 시크릿 읽기) · Secrets Manager admin 비번(random) ·
선택 RDS PostgreSQL(`KC_DB=postgres`).

## RUN guard

이 KIT은 **COPY** 방식이다. 파일을 대상 `set-XX/task-Y/terraform/`(필요하면 `eksctl/`·`k8s/`)로 복사한 뒤 **그 디렉터리에서** 실행한다. 이 addon 디렉터리 자체를 `init`/`apply` 하지 않으므로 기존 Kit의 state를 건드리지 않는다.

```powershell
aws sts get-caller-identity   # EXPECTED ACCOUNT: 대회 당일 지급 계정
aws configure get region      # EXPECTED REGION : 과제지·terraform.tfvars 의 리전
terraform fmt
terraform init                # -upgrade 는 쓰지 않는다
terraform validate
terraform plan                # 기존 리소스에 replace/delete 가 보이면 중단
terraform apply
```

- **VERIFY** = 이 README의 기능 확인. **SCORE** = 해당 세트의 공식 `mark.md`·`mark*.sh`. 서로 대신하지 않는다.
- 기본 RUN에 `destroy`를 넣지 않는다. 점수에 필요한 리소스를 임의로 삭제하지 않는다.
- 공통 실패는 [TROUBLESHOOTING-COMMON](../../TROUBLESHOOTING-COMMON.md). 이 README에는 이 KIT 고유 문제만 둔다.

## 파일

- `vpc.tf` — VPC · 퍼블릭 서브넷 2 · IGW · 퍼블릭 RTB (NAT 없음, EC2 퍼블릭 배치)
- `keycloak.tf` — random_password · Secrets Manager · IAM Role/인스턴스 프로파일 · EC2 SG · EC2 · 선택 RDS(+SG·서브넷 그룹) · outputs
- `alb.tf` — ALB SG · ALB · TG(8080, 헬스 `/realms/master`) · 80 리스너
- `userdata.sh.tpl` — docker 설치 → 시크릿 읽기 → `/etc/keycloak.env` → `docker run ... start`
- `variables.tf` — `addon_kc_*` 변수

## 부착 절차

1. 모듈 디렉토리를 만들고 키트 전부를 `terraform/` 으로 복사한다. `versions.tf` 는 세트 것(`aws ~> 6`, `random ~> 3` 필요 — random 이 없으면 `required_providers` 에 추가).

   ```powershell
   Copy-Item -Recurse _template\task-2\module-4 set-XX\task-2\module-5-keycloak
   Copy-Item shared\addons\keycloak\*.tf, shared\addons\keycloak\userdata.sh.tpl set-XX\task-2\module-5-keycloak\terraform\
   ```

2. `terraform.tfvars` 에 과제지 명시 이름을 넣는다. 기존 VPC 에 얹는 경우 `vpc.tf` 를 지우고 `aws_vpc.addon_kc.id` → `var.<기존 VPC ID>`, `aws_subnet.addon_kc_public` → 기존 퍼블릭 서브넷으로 바꾼다.

   ```hcl
   addon_kc_vpc_name        = "keycloak-vpc"
   addon_kc_vpc_cidr        = "10.30.0.0/16"
   addon_kc_public_subnets = {
     "keycloak-pub-a" = { cidr = "10.30.0.0/24", az = "ap-northeast-2a" }
     "keycloak-pub-b" = { cidr = "10.30.1.0/24", az = "ap-northeast-2b" }
   }
   addon_kc_instance_name   = "keycloak-ec2"
   addon_kc_role_name       = "keycloak-ec2-role"
   addon_kc_alb_name        = "keycloak-alb"
   addon_kc_tg_name         = "keycloak-tg"
   addon_kc_secret_name     = "keycloak/admin"
   addon_kc_admin_username  = "admin"
   addon_kc_image           = "quay.io/keycloak/keycloak:26.5"   # 과제지 지정 버전 있으면 교체
   addon_kc_hostname        = ""                                  # ACM+도메인 있으면 "https://auth.example.com"
   addon_kc_rds_enabled     = false                               # 과제지가 DB 백엔드 요구 시 true
   ```

3. `terraform fmt` → `terraform validate` → `terraform plan` 으로 기존 리소스 diff 없음 확인 → `terraform apply`.
   EC2 부팅 후 이미지 pull + Keycloak 첫 기동(`start` 는 부팅 시 build 를 겸함)에 **3~5분** 걸린다. TG healthy 가 될 때까지 기다린다.

   ```powershell
            aws elbv2 describe-target-health --target-group-arn (terraform output -raw addon_kc_tg_arn 2>$null)

   # 또는 콘솔에서 TG healthy 확인

   ```

4. admin 비번 확인 → ALB DNS 로 로그인 (`http://<ALB DNS>/admin/`).

   ```powershell
   aws secretsmanager get-secret-value --secret-id keycloak/admin --query SecretString --output text
   terraform output -raw addon_kc_alb_dns
   ```

5. realm / client / user 생성 — SSM 세션으로 들어가 컨테이너 안 `kcadm.sh` 를 쓴다 (bastion 없음).

   ```powershell
   aws ssm start-session --target (terraform output -raw addon_kc_instance_id)
   ```

   ```bash
   sudo -i
   ADMIN_PW=$(aws secretsmanager get-secret-value --region ap-northeast-2 --secret-id keycloak/admin --query SecretString --output text | jq -r .password)
   KC="docker exec keycloak /opt/keycloak/bin/kcadm.sh"
   $KC config credentials --server http://localhost:8080 --realm master --user admin --password "$ADMIN_PW"

   # realm
   $KC create realms -s realm=skills -s enabled=true

   # OIDC confidential client (redirect URI 는 과제지 값으로)
   CID=$($KC create clients -r skills -s clientId=skills-app -s protocol=openid-connect \
         -s publicClient=false -s standardFlowEnabled=true -s directAccessGrantsEnabled=true \
         -s 'redirectUris=["*"]' -i)
   $KC get clients/$CID/client-secret -r skills      # client secret 확인

   # 사용자 1명 + 영구 비번
   $KC create users -r skills -s username=skills-user -s enabled=true -s email=skills-user@example.com -s emailVerified=true
   $KC set-password -r skills --username skills-user --new-password 'Skill53##'
   ```

6. 검증 체크리스트.

   ```powershell
   $ALB = terraform output -raw addon_kc_alb_dns
   curl.exe -s -o NUL -w "%{http_code}`n" "http://$ALB/realms/skills/.well-known/openid-configuration"   # 200
   curl.exe -s "http://$ALB/realms/skills/.well-known/openid-configuration" | ConvertFrom-Json | Select issuer
   # password grant 로 토큰 발급 (client secret 은 5단계 출력값)
   curl.exe -s -X POST "http://$ALB/realms/skills/protocol/openid-connect/token" `
     -d client_id=skills-app -d client_secret=<SECRET> -d grant_type=password `
     -d username=skills-user -d "password=Skill53##"
   ```

   - [ ] `http://<ALB>/admin/` admin 로그인 (시크릿의 username/password)
   - [ ] `/realms/skills/.well-known/openid-configuration` 200, `issuer` 가 `http://<ALB>/realms/skills`
   - [ ] realm `skills` · client `skills-app` · 사용자 존재 (`$KC get realms/skills`, `$KC get clients -r skills -q clientId=skills-app`, `$KC get users -r skills`)
   - [ ] 토큰 발급 응답에 `access_token` 포함
   - [ ] HTTPS 는 ACM 인증서가 있을 때만 — 없으면 HTTP 한정(아래 함정)

## 블록

### HTTPS 리스너 (ACM 인증서·도메인이 있을 때만, `alb.tf` 에 추가)

```hcl
resource "aws_lb_listener" "addon_kc_https" {
  load_balancer_arn = aws_lb.addon_kc.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.addon_kc_acm_arn # 변수 추가 필요

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.addon_kc.arn
  }
}
```

`addon_kc_alb_sg` 에 443 ingress 추가, `addon_kc_hostname = "https://<도메인>"` 로 issuer 를 고정한다.

### Keycloak 토큰으로 AWS Role Assume — OIDC IdP + Role trust (확인 필요)

IAM OIDC provider 는 **HTTPS issuer 만** 받는다. 위 HTTPS 리스너 + 도메인이 있을 때만 성립하며, 없으면
이 문항은 HTTP 한정으로 불가능하다고 보고 넘어간다.

```hcl
# issuer = Keycloak realm URL (https 필수). thumbprint 는 AWS 가 자동 검증하나 인자는 필수.
resource "aws_iam_openid_connect_provider" "addon_kc" {
  url             = "https://<도메인>/realms/skills"
  client_id_list  = ["skills-app"]                                      # 토큰 aud
  thumbprint_list = ["0000000000000000000000000000000000000000"]        # 확인 필요: 실제 인증서 thumbprint
}

data "aws_iam_policy_document" "addon_kc_oidc_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.addon_kc.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "<도메인>/realms/skills:aud"
      values   = ["skills-app"]
    }
  }
}

resource "aws_iam_role" "addon_kc_oidc" {
  name               = "keycloak-oidc-role"                             # 과제지 명시 이름
  assume_role_policy = data.aws_iam_policy_document.addon_kc_oidc_assume.json
}
```

검증: `aws sts assume-role-with-web-identity --role-arn <ARN> --role-session-name kc --web-identity-token <access_token>`.
Keycloak 의 access token `aud` 는 기본값이 `account` 라 `skills-app` 이 안 들어간다 — client 에 audience mapper 를
추가해야 한다 (확인 필요: `$KC create clients/$CID/protocol-mappers/models -r skills -s name=aud -s protocol=openid-connect -s protocolMapper=oidc-audience-mapper -s 'config."included.client.audience"=skills-app' -s 'config."access.token.claim"=true'`).

### 관리 포트 헬스체크로 바꾸기 (`alb.tf` TG 안, 선택)

```hcl
# aws_lb_target_group 리소스 health_check 안에:
port = "9000"
path = "/health/ready"
```

`addon_kc_ec2` SG 에 ALB SG → 9000 ingress 를 추가해야 한다. `KC_HEALTH_ENABLED=true` 는 userdata 에 이미 있다.

## 함정

- **Keycloak 26 env 이름**: `KC_BOOTSTRAP_ADMIN_USERNAME` / `KC_BOOTSTRAP_ADMIN_PASSWORD`. 구 `KEYCLOAK_ADMIN*` 는 deprecated (26 에서 경고, 이후 제거). 26.5.2 docs 기준 확인.
- **ALB(HTTP) 뒤 필수 옵션**: `KC_HTTP_ENABLED=true` + `KC_PROXY_HEADERS=xforwarded` (구 `KC_PROXY=edge` 는 deprecated). 없으면 `start` 가 HTTPS 를 요구해 기동 실패하거나 issuer 가 `https://` 로 잡혀 토큰 검증이 깨진다. `KC_HOSTNAME` 미지정 시 `KC_HOSTNAME_STRICT=false` 가 있어야 기동한다.
- **포트 9000 은 프록시하지 않는다** (관리 엔드포인트). ALB 리스너는 8080 만 forward, 헬스체크로만 9000 을 쓴다.
- **`start` vs `start-dev`**: `start-dev` 는 프로덕션 금지 경고 + 캐시 미동작. `start`(비-optimized) 는 부팅 시 build 를 겸해 첫 기동이 1~2분 더 걸린다. 이미지 pull 포함 3~5분 전까지 TG unhealthy 가 정상.
- **DB 없음 = 데이터 비영속**: `addon_kc_rds_enabled=false` 면 컨테이너 내장 dev-file DB. 컨테이너를 지우면 realm 이 사라진다(재부팅은 `--restart always` 로 유지). 채점 전 realm 재생성 여부를 확인한다. RDS 옵션은 생성 5~10분 추가, `KC_DB_URL` 은 `jdbc:postgresql://<host>:5432/<db>`.
- **Secrets Manager `recovery_window_in_days = 0`**: 이름 충돌 방지용. 과제지가 복구 기간을 요구하면 tfvars 가 아니라 `keycloak.tf` 에서 바꾼다.
- **t3.micro 금지**: JVM 이 OOM 으로 죽는다. `t3.small` 이상.
- **퍼블릭 배치**: NAT 없이 EC2 에 퍼블릭 IP 를 준다. 과제지가 "프라이빗 서브넷 + NAT" 를 요구하면 set-02 task-2 module-2 `vpc.tf` 의 NAT·priv RTB 블록을 가져오고 `map_public_ip_on_launch` 를 끈다 — 변경 시 EC2 ⚠ 재생성.
- **이름 정확 일치**: VPC·서브넷·EC2·ALB·TG·IAM Role·시크릿 이름은 전부 tfvars. ALB 이름 32자 제한.
- **IAM OIDC provider 는 HTTPS issuer 전용** — ACM·도메인이 없으면 Role Assume 문항은 구현 불가. thumbprint·audience mapper 는 "확인 필요".
- **RDS 재생성**: `engine_version` major 변경·`db_name` 변경은 ⚠ 재생성. 퍼블릭 서브넷의 서브넷 그룹을 프라이빗으로 옮겨도 ⚠ 재생성.
- userdata 변경은 `aws_instance` ⚠ 재생성(`user_data_replace_on_change` 기본 false 라 in-place 로 보이지만 반영은 안 된다) — 바꾸면 `terraform taint` 또는 `-replace=aws_instance.addon_kc`.

## 실전 구현 (참고용)

없음. 원본 패턴: set-02 task-2 module-2-analytics `terraform/{vpc,ec2,alb,iam,security}.tf`·`userdata.sh.tpl`,
set-08 task-2 module-1-nosql `terraform/secrets.tf`.
