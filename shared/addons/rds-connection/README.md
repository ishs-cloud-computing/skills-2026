# rds-connection 부착 스니펫

2과제 카탈로그 8 "RDS Connection (RDS, VPC)" 스타터 키트 — 저장소에 구현이 없는 모듈.
당일 모듈 5·6 으로 출제되면 `_template/task-2/module-4` 를 복사한 빈 모듈의 `terraform/` 에 통째로 넣고 시작한다.
자족적(VPC 포함): RDS MySQL + Secrets Manager + 파라미터 그룹 + RDS Proxy(선택) + 클라이언트 EC2(private·SSM) + SG 체인 + RDS 이벤트 구독(선택).

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

- `vpc.tf` — VPC · public 1(NAT) · private 2AZ · RTB
- `sg.tf` — SG 체인 (클라이언트 → Proxy → RDS, DB 포트만 SG 참조)
- `rds.tf` — random_password · Secrets Manager · DB 서브넷 그룹 · 파라미터 그룹 · `aws_db_instance` · (선택) SNS + `aws_db_event_subscription`
- `rds-proxy.tf` — Proxy Role/정책 · `aws_db_proxy` · 기본 타깃 그룹 · 타깃 (`addon_rds_proxy_enabled`)
- `ec2.tf` — 클라이언트 EC2 (AL2023, SSM Role, Secret 읽기 정책, IAM 인증 시 `rds-db:connect`)
- `userdata.sh.tftpl` — `mariadb105`·`jq` 설치 + `/usr/local/bin/db-test.sh`
- `outputs.tf` — RDS 엔드포인트 · Proxy 엔드포인트 · 클라이언트 인스턴스 ID
- `variables.tf` — `addon_rds_*` 변수

## 부착 절차

1. 키트 파일 전부를 `set-XX/task-2/module-N-rds/terraform/` 으로 복사한다. `versions.tf` 는 `_template` 것(aws ~> 6.0 + random ~> 3.0, 리전 변수)을 쓴다.
   기존 세트 VPC 에 붙일 때는 `vpc.tf` 를 지우고 `aws_vpc.addon_rds.id` → `aws_vpc.<기존>.id`, `aws_subnet.addon_rds_private` → 기존 프라이빗 서브넷 map 으로 바꾼다.
2. `terraform.tfvars` 에 과제지 명시값을 넣는다 (이름 정확 일치가 채점 항목).

   ```hcl
   addon_rds_name_prefix = "skills-rds"
   addon_rds_vpc_cidr    = "10.60.0.0/16"
   addon_rds_public_subnet = { cidr = "10.60.0.0/24", az = "ap-northeast-2a" }
   addon_rds_private_subnets = {
     "skills-rds-private-a" = { cidr = "10.60.1.0/24", az = "ap-northeast-2a" }
     "skills-rds-private-b" = { cidr = "10.60.2.0/24", az = "ap-northeast-2c" }
   }

   addon_rds_identifier            = "skills-rds-instance"
   addon_rds_engine_version        = "8.0"          # 과제지 명시 버전
   addon_rds_parameter_group_family = "mysql8.0"
   addon_rds_parameters            = { require_secure_transport = "1" }   # 과제지 요구 시만
   addon_rds_db_name               = "skillsdb"
   addon_rds_username              = "admin"
   addon_rds_multi_az              = false          # 요구 시 true (+10분)
   addon_rds_backup_retention_days = 7
   addon_rds_deletion_protection   = false          # 요구 시 true, teardown 전 false 로 apply
   addon_rds_iam_auth              = false
   addon_rds_secret_name           = "skills-rds-credentials"

   addon_rds_proxy_enabled  = true
   addon_rds_proxy_name     = "skills-rds-proxy"
   addon_rds_proxy_iam_auth = false

   addon_rds_client_ec2_name = "skills-rds-client"

   addon_rds_event_topic_name = ""                  # 요구 시 "skills-rds-events"
   addon_rds_event_email      = ""
   ```
3. `terraform fmt` → `terraform validate` → `terraform plan` (신규 모듈이면 전부 `+`, 기존 세트 VPC 에 붙였으면 기존 리소스 diff 없음 확인) → `terraform apply`. RDS 생성 ~10분(Multi-AZ ~20분), Proxy ~5분.
4. 연결 테스트 — 클라이언트 EC2 에서 `db-test.sh` 실행 (Session Manager plugin 없이 `send-command` 로):

   ```powershell
   $ID = terraform output -raw addon_rds_client_instance_id
   $CMD = aws ssm send-command --instance-ids $ID --document-name AWS-RunShellScript --parameters 'commands=["/usr/local/bin/db-test.sh"]' --query Command.CommandId --output text
   aws ssm get-command-invocation --command-id $CMD --instance-id $ID --query '[Status,StandardOutputContent,StandardErrorContent]' --output text
   ```

   `VERSION()` 과 `@@hostname` 이 찍히면 성공. Session Manager plugin 이 있으면 `aws ssm start-session --target $ID` 후 직접 실행.
5. 채점 체크리스트 (`aws rds describe-db-instances --db-instance-identifier <id>` 로 확인):

   | 항목 | 확인 |
   | --- | --- |
   | 엔진·버전 | `Engine`=mysql, `EngineVersion` 과제지 일치 |
   | Multi-AZ | `MultiAZ` |
   | 스토리지 암호화 | `StorageEncrypted`=true |
   | 퍼블릭 차단 | `PubliclyAccessible`=false, DB SG 에 CIDR 인바운드 없음 |
   | 백업·삭제보호 | `BackupRetentionPeriod`, `DeletionProtection` |
   | 파라미터 그룹 | `DBParameterGroups[].DBParameterGroupName` 이 커스텀 그룹 |
   | Secrets | `aws secretsmanager get-secret-value --secret-id <name>` 에 username/password/host |
   | Proxy | `aws rds describe-db-proxies` `Status`=available, `describe-db-proxy-targets` `TargetHealth.State`=AVAILABLE |
   | Proxy 엔드포인트 연결 | 4번 출력의 `@@hostname` 이 RDS 호스트 (Proxy 경유) |
   | IAM DB 인증 | `IAMDatabaseAuthenticationEnabled`=true, 아래 "블록" 의 사용자 생성 후 `db-test.sh iam <user>` |
   | RDS Event 구독 | `aws rds describe-event-subscriptions` `Status`=active, SNS 이메일 Confirmed |

## 블록

IAM DB 인증 사용자 (과제지가 요구할 때, `db-test.sh` 마스터 접속 후 SQL 로):

```sql
CREATE USER 'iam_user'@'%' IDENTIFIED WITH AWSAuthenticationPlugin AS 'RDS';
GRANT SELECT ON skillsdb.* TO 'iam_user'@'%';
```

RDS 스토리지를 CMK 로 (kms/ 키트와 조합, 생성 시에만):

```hcl
# aws_db_instance 리소스 안에:
kms_key_id = aws_kms_key.addon.arn
```

Proxy 없이 인스턴스 직결만 요구되면 `addon_rds_proxy_enabled = false` — Proxy·SG·Role 전부 생성 안 되고 EC2 테스트는 인스턴스 엔드포인트로 간다.

## 함정

- **전부 신규 리소스.** 다음 값 변경은 ⚠ 재생성: `addon_rds_identifier`(RDS·SG·PG 이름), `addon_rds_secret_name`, `addon_rds_proxy_name`, `addon_rds_client_ec2_name`, `addon_rds_username`, 서브넷 map key. `multi_az`·`backup_retention`·`deletion_protection`·`iam_auth`·파라미터는 in-place (`apply_immediately = true` 라 바로 반영, 수 분 `modifying`).
- 엔진 버전 문자열 `"8.0"` 은 최신 마이너가 자동 선택되고 이후 plan 에 diff 가 나지 않는다. 과제지가 `8.0.39` 처럼 마이너까지 지정하면 그대로 넣는다 — 지원 종료 버전이면 `aws rds describe-db-engine-versions --engine mysql --query 'DBEngineVersions[].EngineVersion'` 로 확인.
- 파라미터 그룹 family 는 버전 메이저와 맞아야 한다 (`mysql8.0`·`mysql8.4`). 불일치는 apply 실패.
- `deletion_protection = true` 상태로는 `terraform destroy` 가 실패한다. teardown 전에 false 로 apply.
- Secrets Manager `recovery_window_in_days = 0` — 삭제 즉시 이름 재사용 가능. 기본(30일)으로 바꾸면 재생성 시 이름 충돌.
- Proxy 는 **서로 다른 AZ 서브넷 2개** 필수. 또 secret version·Role 정책보다 먼저 뜨면 타깃이 `AUTH_FAILURE`/UNAVAILABLE — `depends_on` 유지(task-3 실측). 타깃 AVAILABLE 까지 생성 후 수 분.
- Proxy IAM 인증(`REQUIRED`)은 TLS 강제(`require_tls = true` 로 자동 연동). 비밀번호 접속도 `--ssl` 이 필요해진다 — `db-test.sh` 기본 경로는 `--ssl` 없이 붙으므로 IAM 모드에서는 `iam` 서브커맨드로만 테스트.
- `mariadb105` 의 `--enable-cleartext-plugin` 옵션명은 **확인 필요** — 실패하면 `mysql_clear_password` 플러그인 로드 오류가 뜬다. IAM 인증 채점이 걸리면 우선 `aws rds generate-db-auth-token` 이 토큰을 내는지만 확인하고 접속은 워크벤치 대체.
- 클라이언트 EC2 의 user-data 는 `db_host` 를 포함하므로 Proxy on/off 전환 시 EC2 재생성. SSM 등록까지 부팅 후 ~2분 — 바로 `send-command` 하면 `InvalidInstanceId`.
- private 서브넷이라 NAT 가 없으면 `dnf`·SSM 모두 실패. NAT 없이 가려면 ssm·ssmmessages·ec2messages 인터페이스 엔드포인트 3개 + `mariadb105` 를 못 받으니 권장하지 않음.
- RDS 이벤트 SNS 이메일은 수신자가 확인 링크를 눌러야 `Confirmed`. `event_categories` 는 `aws rds describe-event-categories --source-type db-instance` 목록만 허용.
- 채점 스크립트가 SG 인바운드를 "특정 SG 참조" 가 아니라 "CIDR" 로 읽을 수도 있다 — 과제지가 "EC2 서브넷 CIDR 에서만 허용" 식이면 `aws_vpc_security_group_ingress_rule` 의 `referenced_security_group_id` 를 `cidr_ipv4` 로 바꾼다.

## 실전 구현 (참고용)

- task-3 `terraform/rds.tf`·`rds-proxy.tf`·`locals.tf` — RDS MySQL + Proxy + Secret (db.t3.micro, MYSQL_NATIVE_PASSWORD 실측)
- set-08 task-2 module-1-nosql `terraform/secrets.tf`·`ec2.tf`·`iam.tf`·`userdata.sh.tftpl` — random_password Secret, 클라이언트 EC2 + 최소 권한 Role
- set-02 task-2 module-2-analytics `terraform/vpc.tf` — 2AZ VPC·단일 NAT 패턴
