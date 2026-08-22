# docdb-hardening 부착 스니펫

**STATUS:** `VALIDATED` — `terraform validate` 통과 (2026-08-22). AWS 에 apply 한 검증은 아니다.

## USE WHEN

기존 DocumentDB 클러스터에 커스텀 파라미터 그룹(tls·audit_logs·profiler)·CloudWatch 로그 내보내기·
삭제 방지·백업 윈도우를 붙이고 읽기 인스턴스를 count 로 늘린다. set-08 m1(NoSQL) 후보에 대응.

## CHANGE — 당일 고치는 값

`terraform.tfvars` 에 넣는다. **필수 0개**는 채우지 않으면 apply 되지 않는다.

| 변수 | 기본값 | 무엇 |
| --- | --- | --- |
| `addon_docdb_parameter_group_name` | `"skills-docdb-params"` | 클러스터 파라미터 그룹 이름. 과제지 명시 이름과 정확히 일치시킨다 |
| `addon_docdb_family` | `"docdb5.0"` | 파라미터 그룹 family. 클러스터 engine_version 의 메이저와 맞춘다 (5.0.x → docdb5.0, 4.0.0 → docdb4.0). set-08 m1 은 engine_version 미지정 = 기본값(5.0) |
| `addon_docdb_tls` | `true` | tls 파라미터. false 는 지급 앱(tls=True)의 접속을 깨뜨린다 — 과제지가 명시할 때만 끈다 |
| `addon_docdb_audit_logs` | `true` | audit_logs 파라미터. 클러스터 enabled_cloudwatch_logs_exports 에 audit 도 같이 넣어야 내보내진다 |
| `addon_docdb_profiler` | `false` | profiler 파라미터 (느린 쿼리 로그). enabled_cloudwatch_logs_exports 에 profiler 도 같이 |
| `addon_docdb_profiler_threshold_ms` | `100` | profiler 가 기록할 최소 실행 시간 (ms, 50~2147483646) |
| `addon_docdb_cluster_identifier` | `""` | 읽기 인스턴스를 붙일 기존 클러스터 식별자 (aws_docdb_cluster.<기존>.id). reader_count 0 이면 미사용 |
| `addon_docdb_reader_count` | `0` | 추가할 읽기 인스턴스 개수. 0 이면 파라미터 그룹만 만든다 |
| `addon_docdb_reader_identifier_prefix` | `"skills-docdb-reader"` | 읽기 인스턴스 식별자 접두어 — <prefix>-1, -2 ... 과제지 명시 이름에 맞춘다 |
| `addon_docdb_reader_instance_class` | `"db.t3.medium"` | 읽기 인스턴스 클래스. 기존 primary 와 같은 값이 무난 |

## KEEP — 건드리지 않는다

- 기존 세트의 리소스·이름·CIDR. 이름이 충돌하면 기존 것을 지우지 말고 **이 KIT 쪽 변수를 리네임**한다.
- 공식 지급물 — `provided/`, `task.md`, `mark.md`, `mark*.sh`.
- `plan` 에 기존 리소스의 replace/delete 가 보이면 apply 하지 말고 멈춘다.

## CHECK — apply 전 계정·리전

```powershell
aws sts get-caller-identity   # EXPECTED ACCOUNT: 대회 당일 지급 계정
aws configure get region      # EXPECTED REGION : 과제지·terraform.tfvars 의 리전
```

## RUN

이 KIT은 **COPY** 방식이다. 파일을 대상 `set-XX/task-Y/terraform/`(필요하면 `eksctl/`·`k8s/`)로 복사한 뒤 **그 디렉터리에서** 실행한다. 이 addon 디렉터리 자체는 `init`/`apply` 대상이 아니므로 기존 Kit의 state를 건드리지 않는다.

```powershell
terraform fmt
terraform init                # -upgrade 는 쓰지 않는다
terraform validate
terraform plan                # 기존 리소스에 replace/delete 가 보이면 중단
terraform apply
```

복사할 파일과 순서는 아래 본문을 따른다.

## VERIFY / SCORE

- **VERIFY** = 이 README 본문의 기능 확인. **SCORE** = 해당 세트의 공식 `mark.md`·`mark*.sh`. 서로 대신하지 않는다.
- 기본 RUN에 `destroy`를 넣지 않는다. 점수에 필요한 리소스를 임의로 삭제하지 않는다.
- 공통 실패는 [TROUBLESHOOTING-COMMON](../../TROUBLESHOOTING-COMMON.md). 아래 함정은 이 KIT 고유 문제다.

## 파일

- `docdb.tf` — `aws_docdb_cluster_parameter_group`(tls/audit_logs/profiler/profiler_threshold_ms) · `aws_docdb_cluster_instance` 읽기 인스턴스(count)
- `variables.tf` — `addon_docdb_*` 변수

클러스터 안 인자(파라미터 그룹 연결·로그 내보내기·삭제 방지·백업 윈도우)는 아래 "블록" 을 기존 `aws_docdb_cluster` 에 붙인다.

## 부착 절차

1. `docdb.tf`·`variables.tf` 를 `set-XX/task-2/module-N-<name>/terraform/` 으로 복사한다.
2. 클러스터 엔진 버전을 확인해 family 를 맞춘다.

   ```powershell
   aws docdb describe-db-clusters --db-cluster-identifier <클러스터> --query 'DBClusters[0].[EngineVersion,DBClusterParameterGroup]'
   ```
3. `terraform.tfvars` 에 값을 넣는다. 같은 루트 모듈이면 `var.addon_docdb_cluster_identifier` 를 `aws_docdb_cluster.<기존>.id` 로 바꾼다.

   ```hcl
   addon_docdb_parameter_group_name  = "skills-nosql-docdb-params"
   addon_docdb_family                = "docdb5.0"
   addon_docdb_tls                   = true
   addon_docdb_audit_logs            = true
   addon_docdb_profiler              = true
   addon_docdb_profiler_threshold_ms = 100
   addon_docdb_cluster_identifier       = "skills-nosql-docdb-cluster"
   addon_docdb_reader_count             = 1
   addon_docdb_reader_identifier_prefix = "skills-nosql-docdb-reader"   # 기존 primary 식별자와 겹치지 않게
   addon_docdb_reader_instance_class    = "db.t3.medium"
   ```
4. 아래 "블록" 을 `aws_docdb_cluster.<기존>` 안에 붙인다.
5. `terraform fmt` → `terraform validate` → `terraform plan` 으로 클러스터가 `update in-place` 인지 확인 → `terraform apply`.
6. static 파라미터(tls)를 바꿨으면 인스턴스를 재부팅한다.

   ```powershell
   aws docdb reboot-db-instance --db-instance-identifier <인스턴스>
   ```
7. 검증:

   ```powershell
   aws docdb describe-db-clusters --db-cluster-identifier <클러스터> --query 'DBClusters[0].[DBClusterParameterGroup,EnabledCloudwatchLogsExports,DeletionProtection,PreferredBackupWindow,BackupRetentionPeriod,DBClusterMembers[].[DBInstanceIdentifier,IsClusterWriter]]'
   aws docdb describe-db-cluster-parameters --db-cluster-parameter-group-name <그룹> --query "Parameters[?ParameterName=='tls' || ParameterName=='audit_logs' || ParameterName=='profiler'].[ParameterName,ParameterValue,ApplyMethod]"
   aws docdb describe-db-instances --filters Name=db-cluster-id,Values=<클러스터> --query 'DBInstances[].[DBInstanceIdentifier,DBParameterGroups[0].ParameterApplyStatus]'   # pending-reboot 면 6번
   aws logs describe-log-groups --log-group-name-prefix /aws/docdb/<클러스터>/
   ```

## 블록

전부 `aws_docdb_cluster.<기존>` 리소스 안에 넣는다. 모두 in-place.

```hcl
# aws_docdb_cluster 리소스 안에: 커스텀 파라미터 그룹 연결 + 로그 내보내기
db_cluster_parameter_group_name = aws_docdb_cluster_parameter_group.addon.name
enabled_cloudwatch_logs_exports = ["audit", "profiler"] # 파라미터 그룹에서 켠 것만
```

```hcl
# aws_docdb_cluster 리소스 안에: 삭제 방지
deletion_protection = true
```

```hcl
# aws_docdb_cluster 리소스 안에: 백업 (UTC, 30분 이상, 유지보수 윈도우와 겹치면 안 됨)
backup_retention_period      = 7
preferred_backup_window      = "18:00-19:00"         # KST 03:00-04:00
preferred_maintenance_window = "sun:19:30-sun:20:30"
apply_immediately            = true
```

## TROUBLESHOOT — 이 KIT 고유 함정
- 전부 in-place. 단 파라미터 그룹 `name`·`family` 변경은 ⚠ 재생성(그룹만 — 클러스터는 남지만 연결이 끊겼다 붙는다).
- **family ≠ 엔진 메이저** 면 apply 시 `InvalidParameterCombination`. 기본 `docdb5.0` 은 engine_version 미지정(최신 기본) 클러스터 기준 — 2번 명령으로 확인한다. 확인 필요: 대회 당일 기본 엔진이 5.0 이 아니면 tfvars 로 바꾼다.
- `tls` 는 static → `pending-reboot`. 재부팅 전까지 채점 스크립트가 파라미터 값만 보면 통과하지만 실제 접속 동작은 옛값. `audit_logs`·`profiler` 는 dynamic 이라 즉시 반영.
- 로그는 **파라미터 그룹 enabled + `enabled_cloudwatch_logs_exports` 둘 다** 있어야 `/aws/docdb/<클러스터>/audit`·`/profiler` 로 간다. 한쪽만 켜면 로그 그룹이 안 생긴다. 로그 그룹은 자동 생성(보존 무기한) — 보존 기간이 채점이면 `aws_cloudwatch_log_group` 을 같은 이름으로 미리 만든다.
- `tls = false` 는 지급 앱(set-08 `docdb_client.py` 가 `tls=True`)의 접속을 끊는다 — 기능 검증 전체 실패. 과제지가 "TLS 비활성" 을 명시하지 않는 한 건드리지 않는다.
- `deletion_protection = true` 면 `terraform destroy` 실패 — teardown 전 false 로 apply. `skip_final_snapshot = true` 도 유지.
- 백업 윈도우는 `hh24:mi-hh24:mi` UTC, 최소 30분, 유지보수 윈도우(`ddd:hh24:mi-ddd:hh24:mi`)와 겹치면 거부. `apply_immediately` 없으면 다음 유지보수 윈도우까지 반영이 밀린다 — 채점 전 반영되려면 true.
- 읽기 인스턴스 식별자는 계정·리전 내 유일. set-08 m1 의 primary 가 `skills-nosql-docdb-instance-1` 이라 접두어를 같게 주면 `-1` 이 충돌한다. 인스턴스 생성은 약 10분.
- set-08 m1 채점 1-1 이 인스턴스 개수/식별자를 정확 일치로 보는지 mark 를 먼저 확인 — 정확 일치면 reader 추가가 기존 항목을 깨뜨린다.

## 실전 구현 (참고용)

- set-08 task-2 module-1-nosql `terraform/docdb.tf`(KMS 암호화·백업 보존·primary 1개, 기본 파라미터 그룹)
- 커스텀 파라미터 그룹·로그 내보내기·reader 실전 구현 없음
