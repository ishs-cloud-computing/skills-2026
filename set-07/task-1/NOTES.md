# set-07 / task-1

> 이 과제의 설계 이력. squash merge로 중간 커밋이 사라지므로 여기가 유일한 기록이다.
> git이 담는 "무엇이 바뀌었나"는 적지 마라. git이 못 담는 "왜"만 적는다.

## 현재 상태
<!-- 덮어쓴다. 코드와 어긋난 줄은 지우고 다시 쓴다. append 금지. -->

- 구성: terraform(단일 리전 종합 인프라) + eksctl(private cluster, Pod Identity) + k8s(app/logging/monitoring).
  머신 3분할 — 본 PC(PS7: terraform·eksctl·시드·정리) / 일반 CloudShell(이미지 빌드) /
  `unicorn-mark` CloudShell VPC environment(helm·kubectl·채점). **작업용 bastion 없음.**
- 미해결: 배포 실측 미수행 — apply·`mark.sh` 결과를 받으면 아래 채점 커버리지와 소요시간을 채운다.
- 채점 신원은 PowerUser~Administrator 수준 **IAM 사용자**의 CloudShell 이다(2026-08-04 답변). 본 PC 가
  클러스터를 만들므로 본 PC 신원이 그 IAM 사용자와 같아야 하고, 어긋나면 access entry 로 사후 보정한다.
- 새 필수 절차: eksctl 이 fully-private 클러스터를 public+private 로 만든 뒤 public 을 끄므로,
  생성 후 `endpointPublicAccess=false` 확인이 채점 6-1-A 방어선이다(런북 step 3 말미).

## 채점 커버리지
<!-- mark.sh / mark/markN.sh 항목 대비 현재 구현이 어디까지 왔는지. -->

정정(errata) 대비 — `set-07/errata/1과제.txt` 12건 전부 판정 완료. 근거는 정정 로그 표.
2026-08-21 재배포본 PDF 기준으로 재확인했다(반영/미반영 목록은 아래 정정 로그 2026-08-21 절).

| 정정 # | 채점항목 | 판정 | 근거 |
|--------|---------|------|------|
| 0 | 6-1-A | 영향없음 | `eksctl/cluster.yaml:22-25` |
| 1 | 9-1-A | 영향없음 | `terraform/iam.tf:195,205,214,222` (액션 와일드카드 0) |
| 2 | 12-1-A | 수정완료(07-31) | `k8s/logging/fluent-bit.yaml:82`, `eksctl/cluster.yaml:104-107` |
| 3 | 8-6-A, 12-2-A | 수정완료(07-31) | `terraform/waf.tf:41-54` |
| 4 | 4-1-A, 8-3/8-4-A | 영향없음 | `terraform/dynamodb.tf:32-37`, `terraform/lambda/index.py:46` |
| 5 | 8-2/8-3/10-1/12-1/12-2-A | 영향없음 | `terraform/cloudfront.tf:47` |
| 6 | 9-1-A | 영향없음 | `terraform/iam.tf:227-231` (인라인) |
| 7 | 12-1-A | 영향없음 | 문구 변경만 |
| 8 | 6-3-A | 영향없음 | `k8s/app/service.yaml:11` |
| 9 | 절차 | 영향없음 | `README.md` step 9 주석 |
| 10 | 9-2-A | 수정완료 | `mark.sh` (재배포본 = 정정본) |
| 11 | 12-1-A | 영향없음 | 채점 측 지침 |
| 12 | 12-1-A | 수정완료 | `k8s/logging/fluent-bit.yaml:106`, `mark.sh:123` |

배포 실측 대비 — [ ] 미실행. `bash mark.sh` 결과 수신 후 항목별로 채운다.

## 실측 소요시간
<!-- 감이 아니라 숫자로. 무엇을 미리 만들어둘지 판단 근거가 된다. -->

- terraform apply:
- EKS 노드 준비:
- 기타 병목:

---
## 정정 로그
<!-- 과제지·채점지의 오류/정정. -->

정정 정본은 `set-07/errata/1과제.txt` 이고, 배경·"수정없음" 판정·답변과 정본이 어긋난 지점은
`set-07/changelog.txt` 에 있다. **2026-08-21 부터 task-1 의 `task.pdf`·`mark.pdf`·`mark.sh` 는
재배포본이 정본**이며, 전사본 `task.md`·`mark.md` 도 재배포본을 따라간다(아래 2026-08-21 절).
task-2 도 같은 날 재배포돼 채점 스크립트 사본이 `mark3.sh`·`mark4.sh` 로 흡수됐다. 다만 **제공파일은
재배포되지 않아** `provided/module-4/Dockerfile-2026-08-01` 만 날짜 접미사 사본으로 남는다
(`set-07/task-2/NOTES.md` 정정 로그).

### 2026-08-21 과제지·채점지 재배포본 수령 (출처: 출제자 재배포 PDF 2종)

1과제 **과제지·채점지 PDF 수정본**이 재배포되어, `set-07/changelog.txt` 첫 줄이 적어둔
"수정본이 재배포되지 않습니다"라는 전제가 깨졌다. 그 파일은 질의·답변 배경을 담는 문서라
그대로 두고, 재배포 사실과 대조 결과는 여기에만 남긴다. 전사본 `task.md`·`mark.md` 와
`mark.sh` 는 재배포본 기준으로 갱신했다.
2과제는 재배포본이 오지 않아 `errata/2과제.txt` 가 그대로 정본이다.

| 구분 | 내용 | 구현 영향 |
|---|---|---|
| 채점 스크립트 | 재배포본 본문이 `mark-2026-08-10.sh` 와 **완전 동일** — 별도 정정본을 유지할 이유가 사라져 `mark.sh` 를 그 내용으로 덮고 날짜 접미사 사본을 삭제했다(런북 참조도 `mark.sh` 로 통일) | **없음** — 스크립트 내용 자체는 그대로 |
| 반영된 정정 | 2, 3, 5, 6, 7, 8, 9, 10, 11, 12 | **없음** — 이미 전부 판정·반영 완료 |
| 미반영 정정 0 | 8번 Security 의 "Access Entry 사용, aws-auth 미사용" 지문이 **삭제되지 않고 남아 있다** | **없음** — 저장소는 이미 `eksctl/cluster.yaml` `authenticationMode: API`. 강제가 되살아나도 현재 구성이 그 강제를 만족한다 |
| 미반영 정정 1 ★ | 11번이 "Inline Policy 를 사용하며, 와일드카드 액션 **및 리소스**는 사용해서는 안 됩니다." — 정정 6 만 반영되고 **정정 1(리소스 와일드카드 허용)이 되돌아갔다** | **있음(축소)** — `eks:DescribeCluster` 는 `cluster` 를 **필수 리소스 타입**으로 가지므로 `local.cluster_arn` 으로 한정했다(`terraform/iam.tf:219-224`, 2026-08-21 수정 · 근거 SAR `list_eks.html` Actions 표 `DescribeCluster … cluster*`). 남는 `Resource:"*"` 는 `ec2:DescribeVpcs` 한 건뿐이며(`terraform/iam.tf:211-216`), SAR `list_ec2.html` 에서 이 액션의 리소스 타입 열이 비어 있어 대체 불가다(쓸 수 있는 조건 키는 `ec2:Region` 뿐). 채점 9-1-A 는 Action 목록만 읽고 "`*` 이 없으면 득점"이므로 실채점 손실은 0. 지문 위반으로 감점될 여지는 이 한 건에만 남고, 이의신청 시 위 SAR 을 근거로 쓴다. — 주의: EC2 `Describe*` 가 **전부** 리소스 레벨 미지원인 것은 아니다(`DescribeVpcAttribute` 는 `vpc*` 지원). 액션 단위로 확인할 것 |
| 미반영 정정 4 | 6번 Database 의 "Lambda 를 통한 예약 조회를 지원하기 위해" 문장이 남아 있다 | **없음** — 문장만 삭제 대상이었다. Lambda 는 PK `get_item`, GSI 는 4-1-A 존재 확인만 |
| 신규 지문 | 8번 Security 가 "Book App **Pod 에 사용되는 Identity Role**" → "Book App 이 사용되는 **Pod Identity Role**" 로 Pod Identity 를 명시 | **없음** — 이미 Pod Identity. 채점 6-3-A 도 `list-pod-identity-associations` 로 확인한다 |

나머지 차이는 전사본의 표현 오차 교정 수준이다(10-1 ALB 괄호 위치, 12 메트릭 문장, 13 Application 문장 등).
채점지 쪽은 유의사항 18·19 추가, 6-3-A 예상 출력 `unicorn-book-app-svc ClusterIP`, 12-1-A 의
`TZ=Asia/Seoul date` 기준선·"출력된 로그가 위와 같고"·"`None` 무시" — 모두 이미 반영된 정정이다.

### 2026-08-10 답변 (출처: `set-07/errata/1과제.txt` 10~12 + `changelog.txt`)

| # | 정정 내용 | 구현 영향 |
|---|-----------|-----------|
| 10 | 9-2-A 채점스크립트를 별첨 1 정정본으로 — 식별용 고정 출력값(`[1] no external-id:` 등) 삭제 | **없음**(라벨만 제거) — 자가채점만 정정본 `mark-2026-08-10.sh` 사용. `mark.sh` 는 최초본이라 그대로 둔다. *(2026-08-21 재배포로 무효 — `mark.sh` 자체가 정정본이 됐다)* 별첨 1 이 요구하는 4단계(external-id 없이 assume → AccessDenied / assume 성공 / `describe-vpcs` 성공 / `describe-instances` 거부)는 `terraform/iam.tf:177-181`(ExternalId `StringEquals` 조건) + `terraform/data.tf:26`(`unicorn-audit-2026<등번호>`) + `terraform/iam.tf:211-224`(Describe 2종만 허용, `describe-instances` 미포함)으로 이미 충족 |
| 11 | 12-1-A 예상 출력에 "`None` 등의 값이 출력될 경우 무시" 추가 | **없음** — `filter-log-events` 페이지네이션이 만드는 값이라 구현이 손댈 수 없다 |
| 12 | 12-1-A 기준선 명령을 `date -u "+…Z"` → `TZ=Asia/Seoul date "+%Y-%m-%dT%H:%M:%S+09:00"` | **있음** — `k8s/logging/fluent-bit.yaml` 의 `reshape.lua` 가 KST 값을 계산하면서 접미사만 `Z` 였다. `+09:00` 으로 변경(결정 로그 2026-08-15 참조). `mark-2026-08-10.sh` 의 기준선 명령도 정정본으로 교체 *(2026-08-21 재배포로 `mark.sh` 에 흡수)* |

`changelog.txt` 2026-08-10 의 `주의:` 3건은 위 표에 흡수했다. 다만 **08-04 의 "과제지 예시 형식(`Z`)에 맞출 것"과
08-10 의 "로그 timestamp 도 `+09:00` 으로 기록할 것"이 정면 충돌**한다 — 후행·구체적인 08-10 을 채택했다(결정 로그).

### 2026-08-04 답변 (출처: `set-07/errata/1과제.txt` 5~9 + `changelog.txt`)

| # | 정정 내용 | 구현 영향 |
|---|-----------|-----------|
| 5 | CloudFront 를 "`unicorn-svc-cf` 이름으로" → "`unicorn-svc-cf` **Comment** 를 가지도록" 생성 | **없음** — Distribution 에는 Name 필드가 없고 처음부터 `terraform/cloudfront.tf:47` `comment = "unicorn-svc-cf"` 다. 채점도 전부 `DistributionList.Items[?Comment=='unicorn-svc-cf']` 로 찾는다(`mark.sh:79,111,130`). `cloudfront.tf:110` 의 `Name` 태그는 무해한 여분이라 남긴다 |
| 6 | 과제지 11 "와일드카드 액션은…" 앞에 "**Inline Policy 를 사용하며,**" 추가 | **없음** — `terraform/iam.tf:227-231` 이 이미 `aws_iam_role_policy`(인라인)다. 채점 9-1-A 가 `aws iam list-role-policies`(인라인 전용)만 쓰므로 고객 관리형으로 붙였으면 0점이었다 |
| 7 | 12-1-A "출력값 **형식**이 위와 같고" → "**출력된 로그**가 위와 같고" | **없음**(문구) — 다만 형식 엄격성이 완화됐다는 근거로 정정 12 판단에 쓰인다. 유의사항 16 에 따라 IP 등 변동값은 무시 |
| 8 | 6-3-A 예상 출력 `unicorn-book-app-svc` → `unicorn-book-app-svc ClusterIP` | **없음** — `k8s/app/service.yaml:11` 이 이미 `type: ClusterIP`. `mark.sh:60` 이 `TYPE:.spec.type` 을 출력하고 있어 출력값도 이미 일치 |
| 9 | 유의사항 19 추가 — `source kubectl-connect` 오류 시 1회에 한해 `rm -rf .kube/` 로 초기화 허용 | **없음**(채점 절차) — 런북 step 9 에 한 줄만 반영. kubeconfig 에 cluster info 가 이미 있으면 덮어쓰지 않는 동작이 원인 |

`changelog.txt` 2026-08-04 의 나머지 `주의:` 판정 —
**12-2-A 재채점**(수정없음): `terraform/waf.tf:83-106` 의 limit 50 / evaluation window 60초가 과제지와 일치하고
채점 스크립트도 60초 대기하므로 영향없음.
**9-2-A 채점 주체**(수정없음): errata 정본에는 없으나 저장소 설계와 어긋나 문서만 고쳤다 — 아래 결정 로그 참조.

### 2026-08-01 답변 (질의 ~2026-07-30 / 출처: `set-07/errata/1과제.txt` + `changelog.txt` 2026-08-01)

- **Platform MRK 리전**: 과제지 4번은 "us-east-1 다중 리전 키"라고 쓰여 있으나, 선수 유의사항 7(모든 리소스
  서울)이 우선이며 "Primary 를 서울에 두고 MRK 로 us-east-1 에서 쓸 수 있게 하라"는 뜻이라는 답변.
  → 구현 변경: 프라이머리를 ap-northeast-2 로, 레플리카를 us-east-1 로 뒤집었다(`terraform/kms.tf`).
- **Timezone**: 채점기준표 표기는 UTC 이나 **채점은 KST 기준**으로 확인한다(정정 2 재확인). 과제지는 KST 기준 풀이 지시.
  → 구현 변경: 아래 정정 2 항목 참조.
- 나머지(WAF override, GSI 문구)는 아래 2026-07-31 정정과 동일 내용.

### 2026-07-31 정정 4건 (출처: `set-07/errata/1과제.txt` 0~4)

- **0) EKS Authentication mode 강제 삭제** — 직종협의회 결과로 "Access Entry 사용, aws-auth 미사용" 지문 삭제.
  → **구현 변경 없음.** 강제가 풀렸을 뿐 금지가 아니고, 채점 CloudShell 접근 경로는 그대로 필요하다.
  `eksctl/cluster.yaml` 의 `authenticationMode: API` + 생성자=채점 신원 전제를 유지한다.
- **1) 리소스 와일드카드 제한 해제** — 과제지 11 "와일드카드 액션 및 리소스" → "와일드카드 액션".
  → **구현 변경 없음.** `unicorn-audit-role` 은 이미 리소스 ARN 을 명시하고, 리소스 레벨 ARN 을 지원하지 않는
  `ec2:DescribeVpcs`/`eks:DescribeCluster` 와 KMS 키 정책에서만 `Resource:"*"` 를 쓴다. 이제 명시적으로 적법.
- **2) 채점 유의사항 18 추가** — "채점기준표에는 Timestamp 의 TZ 가 UTC 기준이나, 채점 시 KST 기준으로 확인".
  → **구현 변경 있음.** fluent-bit 이 UTC 를 강제하고 있었다. 아래 결정 로그 참조.
- **3) WAF rule-level override 허용** — "override action 은 모두 None, rule-level override 없이 적용" 삭제 →
  "필요할 경우 Custom Response 지정을 위해 override 가능, **채점 시 XSS 공격을 진행**함에 유의".
  → **구현 변경 있음.** 아래 결정 로그 참조.
- **4) GSI 문구에서 "Lambda를 통한 예약 조회를 지원하기 위해" 삭제** — 과제지의 논리 오류. 8-3/8-4 채점은
  side effect 우려로 `booking_id` 추출 방식을 유지한다는 답변.
  → **구현 변경 없음.** Lambda 는 PK `get_item` 이고 GSI 는 요구사항대로 존재만 하면 된다(채점 4-1-A).

---
## 결정 로그
<!-- append만. 위 섹션과 달리 절대 수정하지 않는다. 최신이 위로 오게 쌓는다. -->

### 2026-08-21 `eks:DescribeCluster` 를 클러스터 ARN 으로 축소 — 재배포본 11번의 리소스 와일드카드 금지 부활
- 맥락: 재배포본 과제지 11 이 "와일드카드 액션 **및 리소스**는 사용해서는 안 됩니다"로 되돌아갔다(정정 1 미반영).
  기존 주석은 `ec2:DescribeVpcs`·`eks:DescribeCluster` 둘 다 리소스 레벨 ARN 미지원이라고 적었으나 **절반이 틀렸다** —
  SAR `list_eks.html` Actions 표는 `DescribeCluster` 의 리소스 타입을 `cluster*`(필수)로 명시한다.
- 채택: statement 를 둘로 분리. `eks:DescribeCluster` → `local.cluster_arn`(`data.tf:24`, Pod Identity trust 와 공용),
  `ec2:DescribeVpcs` → `"*"` 유지. 와일드카드 리소스가 2개 액션 → 1개로 줄고 채점 영향은 0(9-1-A 는 Action 만 읽는다).
  **VPC statement 를 앞에** 둬 `mark.md:604` 예상 출력의 `ec2:DescribeVpcs eks:Describe` 순서를 맞춘다.
  실측: `aws_iam_policy_document` 는 **statement 순서는 보존하지만 statement 안의 actions 순서는 재정렬**한다 —
  분리 전 `actions = ["ec2:DescribeVpcs", "eks:DescribeCluster"]` 가 실제로는
  `["eks:DescribeCluster","ec2:DescribeVpcs"]` 로 렌더링돼 예상 출력과 **뒤집혀 있었다**.
  분리하면 statement 당 액션이 1개가 되어 순서가 확정된다(부수 효과지만 9-1-A 대조에 유리).
  `mark.sh:97` 의 `Statement[].Action[]` 은 액션이 1개라 `Action` 이 배열이 아닌 문자열로 렌더링돼도
  값을 그대로 뽑는다(jmespath 로 확인: `dynamodb:Query dynamodb:GetItem kms:Decrypt ec2:DescribeVpcs eks:DescribeCluster`).
- 기각: 현행 유지 — 채점 영향은 0 이지만 주석이 사실과 달라 이의신청 근거가 약해진다.
- 기각: `ec2:DescribeVpcs` statement 에 `ec2:Region` 조건 추가 — SAR 상 유일하게 쓸 수 있는 조건 키지만,
  9-2-A 의 `describe-vpcs` 는 **채점자 CloudShell** 에서 호출되므로 리전이 어긋나면 득점 항목이 Deny 로 죽는다.
  지문이 문제 삼는 건 조건이 아니라 와일드카드라 이득 0, 실점 리스크만 있다.
- 참고: EC2 `Describe*` 가 전부 리소스 레벨 미지원이라는 통념은 이제 틀렸다 —
  같은 표에서 `DescribeVpcAttribute` 는 `vpc*`, `DescribeVpcEndpointServicePermissions` 는 `vpc-endpoint-service*` 를 지원한다.

### 2026-08-21 정정본 사본을 없애고 `mark.sh` 하나로 — 재배포본이 원본을 대체했다
- 맥락: 정정 10·12 를 반영한 `mark-2026-08-10.sh` 를 원본 `mark.sh` 옆에 두는 규칙이었다. 원본이
  재배포되지 않는다는 전제에서 "원본은 대조용으로 보존"이 성립했기 때문이다. 2026-08-21 재배포본이
  오면서 전제가 깨졌고, 재배포본 본문은 `mark-2026-08-10.sh` 와 글자까지 같았다.
- 채택: `mark.sh` = 재배포본. 날짜 접미사 사본 삭제. 대회 당일 두 이름을 헷갈릴 여지를 없애는 게
  대조 가치보다 크다 — 런북이 S3 릴레이 tar, `cp ~/`, 자가채점 3곳에서 파일명을 부르고 있었다.
- 기각: 사본을 남기고 `mark.sh` 만 갱신 — 같은 내용 파일이 둘이 되어 이름만 늘어난다.
- 대가: 최초본 대조가 필요하면 git 이력(`git show <이전커밋>:set-07/task-1/mark.sh`)으로만 볼 수 있다.
- 참고: 아래 2026-08-15 항목의 `mark-2026-08-10.sh:27-33,76` 는 이제 `mark.sh` 의 같은 줄을 가리킨다.

### 2026-08-15 S3 릴레이에서 텍스트 제거 — `outputs.json`·`Dockerfile` 은 붙여넣기로
- 맥락: 릴레이가 4개를 나르는데 그중 둘이 텍스트였다. 릴레이가 존재하는 이유는 CloudShell 에 파일을 넣을
  방법이 없어서인데(VPC environment 는 Actions 업로드 자체가 막혀 있고 레포가 비공개라 clone 불가),
  **터미널 붙여넣기는 된다**. `CLAUDE.md:30` 이 "README 는 그대로 복붙 가능한 형태를 유지한다"고 규정하고
  `set-02/task-1/README.md:269-281`(heredoc)·`task-3/README.md:14-15`(`vim` + `:set paste`) 가 선례다.
- 채택: `outputs.json` → 본 PC 가 값을 박아 만든 `.env` heredoc 을 콘솔에 출력해 붙여넣는다.
  CloudShell 쪽 `jq` 블록 10줄이 통째로 사라지고, `outputs.json` 자체가 릴레이에서 빠진다.
  `Dockerfile` → 일반 CloudShell 에서 heredoc 붙여넣기. README 에 내용을 복제하지 않고 자리표시자만 둔다
  (drift 방지) — `wc -l` = 22 대조를 붙여 붙여넣기 무결성을 확인한다.
  릴레이에 남는 건 `unicorn-cs.tgz`(k8s 13파일 + mark 스크립트)와 `book`(8.7 MB) 둘뿐이다.
- 기각: k8s 도 붙여넣기 → 13파일 732줄이라 실패 지점이 많고, README 에 manifest 를 복제하면 drift 가 생긴다.
  본 PC 에서 heredoc 을 생성해 출력하면 drift 는 없지만, `book` 때문에 릴레이는 어차피 남으므로
  **없애는 S3 객체가 0**이다. 붙여넣기 단계만 는다.
- 기각: `book` 을 일반 CloudShell Actions → Upload 로 → 릴레이가 어차피 남으므로 수동 단계만 늘어난다
  (2026-07-27 "이미지 빌드를 일반 CloudShell 로" 항목과 같은 판단).
- 기각: mark 스크립트만 tgz 에서 빼서 붙여넣기(`set-03/task-1/NOTES.md:108-112` 선례) → tgz 는 그대로
  남으므로 S3 객체가 안 줄고 137줄 붙여넣기만 는다. tgz 에 얹혀 가는 한계비용이 0이다.
- 대가: 붙여넣기 경로에 **Windows 클립보드 CRLF** 위험이 새로 생긴다. `sed -i 's/\r$//' ~/.env` 가드를
  블록 끝에 넣고 CloudShell 쪽에 `grep -c $'\r' ~/.env` 확인을 뒀다
  (`set-08/task-2/NOTES.md:58` 이 실측한 함정 — 값 끝 `\r` 로 push 가 조용히 깨진다).
- 덤: CloudFront s3-origin 이 버킷 루트를 서빙하므로 `https://<CF>/_transfer/outputs.json` 이 공개로
  열려 있었다. 그 노출이 사라진다. 채점에는 원래 무관했다 — mark 3-1-A·8-2-A 는 전부 버킷 레벨 API 라
  객체 목록을 보지 않는다(`mark-2026-08-10.sh:27-33,76`). step 8 정리는 위생 목적으로 그대로 남긴다.

### 2026-08-15 작업용 bastion 제거 — eksctl 을 본 PC 로, helm·kubectl 을 `unicorn-mark` CloudShell 로
- 맥락: 런북이 머신을 4분할하며 SSM bastion 을 수동 생성/삭제하고 있었다. 그런데 (a) `task.md:57` 유의사항
  14 가 `unicorn-mark` CloudShell VPC Environment 를 이미 강제하고 "그 쉘 안에서 kubectl 을 조작"하라고
  못박고, (b) `changelog.txt:96-99` 2026-08-04 답변이 "직종설명서 개정본상 스크립트는 **Bastion 대신**
  Admin 수준 IAM 으로 접속한 CloudShell 에서 실행"이라고 명시했다. `task.md`·`mark.md`·`errata/1과제.txt`
  어디에도 bastion 이 없다 — `CLAUDE.md` 기준으로 불필요 리소스 감점 대상이고, 게다가 `t3.small` 이라
  유의사항 12(모든 EC2 t3.medium)와도 어긋났다.
- **"private cluster 라 eksctl 은 VPC 내부에서만 가능하다"가 틀렸다**: eksctl 은 fully-private 클러스터를
  public+private 엔드포인트로 만든 뒤 **모든 작업이 끝나면 public 을 끈다**(eksctl 공식 문서 Limitations).
  같은 `privateCluster.enabled: true` 구성인 `set-03/task-1` 이 본 PC PowerShell 에서 이미 그렇게 돌린다
  (`set-03/task-1/README.md:119-175`). bastion 의 존재 이유였던 전제가 사실이 아니었다.
- 채택: 3분할. 본 PC(terraform·eksctl·시드·정리) / 일반 CloudShell(이미지 빌드) / `unicorn-mark`
  CloudShell(helm·kubectl·채점). 20분짜리 `eksctl create` 가 본 PC 로 빠지면서 CloudShell 이 맡는 건
  helm 3개 + `kubectl apply` 뿐이라, VPC environment 의 비영구 홈·유휴 타임아웃이 더 이상 병목이 아니다.
  VPC 내부 접근이 필요한 리소스는 EKS private API 하나뿐이고(RDS 없음, 내부 ALB 는 CloudFront VPC Origin
  경유, Grafana ALB 는 public, 시드는 공개 CloudFront), 그 경로는 `security.tf:108-143` 의
  `unicorn-mark-sg` → cp-extra-sg 443 이 이미 깔아뒀다 — bastion 은 그 SG 를 빌려 쓰던 것뿐이었다.
  **terraform·eksctl·k8s 코드는 한 줄도 바뀌지 않는다.** 런북 3개 파일만 바뀐다.
- 기각: bastion 유지 → 감점 대상인 데다 `aws login --remote` 자격증명 이관, 상태 백업/복구, 삭제 전
  권한 게이트라는 절차 3개를 계속 지고 간다. 그 3개는 전부 "bastion 신원 ≠ 채점 신원" 을 메우려는
  장치였는데, 생성을 본 PC 로 옮기면 신원 하나로 정리된다.
- 기각: 클러스터를 public+private 로 유지(set-07 task-2 module-3 방식) → `task.md:113` 위반이고
  채점 6-1-A 가 `endpointPublicAccess` 를 직접 읽는다. 0점.
- 대가: eksctl 이 생성 중 public 엔드포인트를 잠깐 연다. **중단되면 켜진 채 남으므로**
  `describe-cluster` 로 `false true` 확인하는 절차가 런북 step 3 말미에 새로 필수가 됐다.
- 대가: 본 PC 신원이 이제 채점 신원과 같아야 한다(기존엔 "계정만 맞으면 무관"이었다).
  신원이 IAM 사용자라 어긋나도 access entry 로 보정된다.
- 대가: CloudShell VPC environment 는 홈이 비영구(20~30분 유휴 시 `$HOME` 삭제)라 세션이 끊기면
  런북 step 4 부트스트랩을 다시 돌려야 한다. 그래서 step 4 를 "통째로 재실행 가능한 한 블록"으로 묶었다.

### 2026-08-15 로그 timestamp 접미사를 `Z` → `+09:00`, 채점 신원 전제를 root → IAM 사용자
- 맥락: 2026-08-04·2026-08-10 정정 8건(errata 5~12)을 구현과 대조했다. 실제로 어긋난 곳은 두 군데뿐이다.
- **timestamp 접미사 `+09:00`**: 채택 — `reshape.lua` 를 `os.date("!…%H:%M:%S", sec+KST_OFFSET) .. "+09:00"` 으로.
  정정 12 가 12-1-A 기준선을 `TZ=Asia/Seoul date "+%Y-%m-%dT%H:%M:%S+09:00"` 로 바꿨다. 값은 이미 KST 였으므로
  접미사만 틀린 상태였는데, 기준선이 `+09:00` 인데 로그가 `Z` 면 **채점자가 로그를 UTC 로 읽어 9시간 차로 판정**할
  여지가 남는다. 오프셋을 맞추면 두 줄의 차가 문자 그대로 몇 초다.
  기각: `Z` 유지 → `task.md:194` 예시·`mark.md:737` 전사본과는 리터럴이 맞지만, 그 둘은 정정 **전** 문서다.
  정정 7 이 "출력값 **형식**" → "출력된 **로그**" 로 완화한 것이 형식 일치를 요구하지 않는다는 근거다.
  기각: 컨테이너 TZ 로 해결 → 2026-08-04 항목과 같은 이유(tzdata 없으면 조용히 UTC).
  대가: 전사본 `mark.md`·`task.md` 의 예시와 리터럴이 다르다. 두 문서는 원본 대조용이라 고치지 않는다.
- **채점 신원 root → IAM 사용자**: 채택 — 런북의 "채점은 root 로 한다" 전제를 걷어냈다. `changelog.txt` 2026-08-04
  `9-2-A 채점 주체` 답변이 "PowerUser 이상 Administrator 이하 IAM 계정, 직종설명서 개정본상 스크립트는 Bastion 이
  아니라 Admin 수준 IAM 으로 접속한 CloudShell 에서 실행"이라고 못박았다. root 는 애초에 Assume Role 을 못 해
  9-2-A 자체가 성립하지 않는다.
  **이 변경으로 위험이 하나 사라진다** — 그동안 step 9 권한 게이트를 반드시 통과시켜야 했던 이유가 "root ARN 은
  access entry 대상으로 문서화돼 있지 않아 사후 보정이 안 될 수 있다"였는데, 신원이 IAM 사용자면
  `create-access-entry` + `associate-access-policy` 가 정상 복구 경로가 된다.
  기각: `eksctl/cluster.yaml` 에 `accessEntries` 를 추가해 채점 principal 을 못박기 →
  `bootstrapClusterCreatorAdminPermissions: true` 와 principal 이 같으면 create 단계에서 중복 엔트리로 실패한다.
  게이트 실패 시 두 줄로 복구되는 지금이 더 안전하다. 환경변수 오타 하나로 클러스터 생성이 깨지는 쪽으로 가지 않는다.
  대가: 정정 정본(errata)에 없는 변경이라 문서만 고쳤다. 구현은 그대로다.

### 2026-08-04 Platform MRK 프라이머리를 서울로, 타임스탬프를 KST 로, WAF XSS 룰에 Custom Response
- 맥락: 2026-07-31 정정 4건과 2026-08-01 답변을 현재 구현과 대조한 결과 세 곳이 어긋났다(위 정정 로그).
- **MRK 프라이머리 swap**: 채택 — 프라이머리 ap-northeast-2 + 레플리카 us-east-1. 유의사항 7 해석이 그렇고,
  채점 2-1-A 가 **서울에서** `alias/unicorn-kms-platform` 의 회전 상태를 읽는다. 회전은 프라이머리에만 설정
  가능하고 AWS 가 레플리카로 복사하는 구조라, 서울이 프라이머리면 `True 90` 이 값 그 자체가 된다.
  기각: 현행 유지(레플리카가 서울) → 복사된 `RotationPeriodInDays` 에 의존하고 유의사항 7 과도 어긋난다.
  대가: `platform_kms_primary_arn` output 을 `platform_kms_use1_arn` 으로 개명(미사용 output 이라 영향 없음).
  `platform_kms_arn`(eksctl·storageclass 치환용)은 이름 그대로라 런북은 안 바뀐다.
- **타임스탬프 KST**: 채택 — `reshape.lua` 를 `os.date("!...", sec + KST_OFFSET)` 로. 포맷(`...Z`)은 과제지
  그대로 두고 값만 KST. 과제지 예시가 근거다 — 앱 access 라인 `2026/06/09 06:16:16`(노드 KST 로컬시각)과
  기대 출력 `2026-06-09T06:16:16Z` 가 같은 값이다. 즉 기대값 자체가 KST 다.
  기각: 컨테이너에 `TZ=Asia/Seoul` 만 주고 `!` 제거 → tzdata 가 없으면 **조용히 UTC 로 돌아간다**.
  산술 오프셋은 실패할 여지가 없다. (한국은 서머타임이 없어 고정 +9 로 충분)
- **앱 컨테이너 시간대**: 채택 — 노드의 `/usr/share/zoneinfo/Asia/Seoul` 을 `/etc/localtime` 으로 hostPath 마운트.
  노드는 KST 지만 **컨테이너는 상속하지 않는다**. `created_at` 은 제공 바이너리가 만들어 확인이 불가능하므로,
  로컬 시각을 쓰는 구현이면 KST 가 되도록 걸어두는 보험이다(UTC 를 명시적으로 쓰면 손쓸 방법이 없다).
  기각: Dockerfile 에 `apk add tzdata` + `TZ` env → 요구사항 7(공개 취약점 0)에 패키지 하나를 새로 얹는다.
- **WAF XSS override**: 채택 — `AWSManagedRulesCommonRuleSet` 의 `CrossSiteScripting_*` 4종에
  `rule_action_override` 로 block + custom response(`unicorn-blocked`). 액션은 그대로 block/403 이라
  8-6-A(상태코드)는 영향이 없고, 차단 본문이 과제지 "차단 시 응답은 403, `Request blocked by Unicorn WAF`" 와
  일치하게 된다. 룰 이름은 변수 `waf_xss_rules` 로 빼 당일 벡터가 늘어도 목록만 고치면 된다.
  기각: 룰 전체를 Count 로 낮추고 별도 커스텀 룰로 차단 → 관리형 룰의 차단 능력을 우리 룰로 재구현해야 한다.
  CloudFront custom error response → 출제자가 "과제 의도에서 벗어난다"고 명시했다.
  대가: `KnownBadInputsRuleSet` 과 CommonRuleSet 의 나머지 룰은 여전히 기본 403 페이지를 반환한다.

### 2026-07-28 bastion 자격증명을 root 액세스 키에서 `aws login --remote` 로 전환
- 맥락: 채점은 root 로 하고(`mark.md` 순번 0 이 `rm -rf ~/.aws` 후 콘솔 세션 자격증명을 그대로 쓴다)
  private cluster 라 생성은 bastion 에서 해야 하므로, bastion 신원도 root 여야 한다. 그런데 런북은 그걸
  root 액세스 키로 맞추고 있었다. Organizations 멤버 계정에서 centralized root access management 가 켜져
  있으면 root 액세스 키 생성·복구가 차단돼 step 4 자체가 실행 불가가 된다.
- 채택: `aws login --remote`(AWS CLI 2.32.0+, 콘솔 자격증명 → 임시 크레덴셜). 얻는 신원은 액세스 키와 같아
  생성자=채점 신원 조건이 그대로 성립하고, 키 없이 콘솔 ID/PW 만으로 된다. `--remote` 는 브라우저 없는
  호스트용이라 SSM 세션에 맞는다. step 4 에 CLI 최신 v2 갱신과 `aws configure list`(TYPE=login) 확인을 넣었다.
- 기각: root 액세스 키 유지 → 키 생성이 막히면 대안이 없다.
  bastion 인스턴스 역할에 작업 권한 부여 → 생성자가 역할 ARN 이 되어 채점 셸(root)과 어긋난다.
  클러스터 생성 전에 채점 CloudShell 을 미리 띄워 ARN 을 대조하는 게이트 신설 → root 는 root 라 대조할
  모호함이 없다. `aws login` 직후 `get-caller-identity` 한 줄이면 같은 실수를 잡는다.
- 대가: CLI 2.32.0 의존(AL2023 기본 버전이 미달일 수 있어 설치 블록이 한 단계 늘었다), 세션 12시간 만료 시
  재로그인, signin 엔드포인트는 VPC Endpoint 가 없어 NAT 경유가 필수다.

### 2026-07-27 bastion 삭제 전 권한 게이트 + 상태 백업으로 복구 가능하게
- 맥락: step 10 이 bastion 을 지운 뒤에야 채점 셸에 kubectl 권한이 없다는 걸 알면 손쓸 방법이 없다.
  private cluster 라 VPC 밖에서는 클러스터에 접근조차 못 한다.
- 채택: "검증 → 백업 → 삭제" 순서 고정. step 9 끝에 채점 셸에서 `kubectl auth can-i '*' '*'` 게이트를 두고,
  step 10-1 에서 `~/.env` + `~/unicorn` 을 tgz 로 묶어 S3 경유로 본 PC 에 회수한 뒤 삭제한다.
- 기각: bastion 을 채점까지 남기기 → 보안 pillar·정리 차원에서 흔적을 남기고 싶지 않다.
  AMI/스냅샷으로 백업 → 리소스가 더 남고, 복구 가치가 있는 건 렌더 결과와 env 뿐이라 과하다.
- 대가: 백업 tgz 가 채점 대상 버킷(`_transfer/`)을 잠깐 경유한다. 최종 보관은 본 PC 이고
  10-2 마지막에 `_transfer/` 를 비우지만, **회수보다 정리를 먼저 하면 복구 불가**가 된다.

### 2026-07-27 자격증명을 "채점 셸과 같은 신원"으로 규정 (root 전제)
- 맥락: 런북이 `aws configure` 에 "선수 IAM 키"를 넣으라고 못박고 있었다. 대회가 root 사용을 금지하지
  않으면 선수는 root 로 운영하므로 실제와 어긋난다. 핵심은 키의 종류가 아니라
  클러스터 생성자 = 채점 CloudShell 신원이 성립하느냐다(`bootstrapClusterCreatorAdminPermissions`).
- 채택: 문구를 신원 일치 조건으로 바꾸고, 어긋났을 때를 step 9 게이트로 잡는다.
- 기각: 항상 전용 IAM 사용자를 만들게 강제 → 대회 지침에 없는 절차를 늘린다.
  access entry 사후 추가에만 의존 → CLI 레퍼런스가 STANDARD 항목에 "every IAM principal type" 을 허용한다고만
  하고 계정 root ARN 은 문서화돼 있지 않다. root 운영 시 이 경로가 보장되지 않는다.
- 대가: root 로 갔다가 게이트에서 걸리면 클러스터 재생성(약 20분)이 최선책일 수 있다.

### 2026-07-27 이미지 빌드를 본 PC → 일반 CloudShell 로 이전
- 맥락: step 2 가 본 PC 에서 `docker buildx build` 를 했는데, CLAUDE.md 대회 환경은 "Docker, WSL 사용 불가".
  셸만 PowerShell 로 옮겨서는 실행 자체가 안 된다.
- 채택: 일반 CloudShell(VPC environment 아님 — Docker·인터넷 egress 둘 다 필요)에서 빌드/푸시.
  재료(`Dockerfile`, `book`)는 이미 있는 S3 릴레이로 넘긴다.
- 기각: set-03 처럼 Actions → Upload file 수동 업로드 → 릴레이가 이미 있는데 수동 단계를 늘릴 이유가 없다.
  bastion 에 docker 설치 → private 서브넷이라 NAT 경유 pull + 인스턴스 타입 상향이 필요하다.
- 대가: 본 PC 의 `app/` 로 `book` 을 복사하던 단계가 사라져 로컬에서 이미지를 시험 빌드할 수 없다.

### 2026-07-27 placeholder 를 `${VAR}` 로 통일하고 k8s 를 rendered/ 일괄 apply 로 전환
- 맥락: eksctl 은 `${VAR}`, k8s 는 `<VAR>` 로 문법이 갈려 있어 검사 패스를 하나로 만들 수 없었다.
  파일별 `sed | kubectl apply -f -` 는 렌더 결과가 파일로 남지 않아 치환 누락을 조용히 통과시킨다.
- 채택: 전부 `${VAR}` 로 통일(변수명은 `~/.env` 에 이미 있는 이름에 맞춤 — 새 env 없음).
  k8s 는 `rendered/` 에 미러 렌더 후 `kubectl apply -R` 한 번. 치환 전 env 선언 검사 + 치환 후 잔여 `${}` 검사.
- 기각: envsubst 단독 → 미선언 변수를 빈 값으로 조용히 치환한다. python3 `expandvars` 는 `${VAR}` 를 그대로
  남겨 사후 검사에 걸리므로 방어가 한 겹 더 있다. gettext 설치를 추가하지 않아도 되는 것은 덤.
  kustomize → 도구를 늘리지 않고 폴더 apply + 번호 prefix 로 충분하다.
- 대가: `apply -R` 이 사전순이라 `app/serviceaccount.yaml` 을 `00-serviceaccount.yaml` 로 개명해야 했다
  (SA 가 Deployment 보다 먼저 와야 한다). 주석 안의 `${VAR}` 도 함께 치환돼 렌더 결과의 주석이 값으로 바뀐다.

### 2026-07-27 본 PC 단계만 PowerShell 7 로, 나머지는 bash 유지
- 맥락: 런북 318줄이 전부 bash 였다. 대회 PC 는 Windows 11 / PowerShell 7 이라 본 PC 단계가 실행되지 않는다.
- 채택: 셸을 머신에 맞춘다 — 본 PC(0·1·3·10)만 PowerShell, bastion·CloudShell 단계(2·4~9)는 실제 호스트가
  Linux 이므로 bash 그대로. 헤더에 `[본 PC·PowerShell]` / `[일반 CloudShell]` / `[bastion]` 라벨을 붙였다.
- 기각: 런북 전체를 PowerShell 로 → bastion·CloudShell 은 AL2023 이라 오답이다.
  set-02 식 전체 미러 README.linux.md → set-07 은 단계 대부분이 Linux 호스트라 중복만 커지고 드리프트를 부른다.
  set-03 식 delta-only(본 PC 단계만)로 갔다.
- 대가: 본 PC 단계를 고칠 때 README.md 와 README.linux.md 두 곳을 같이 고쳐야 한다(4개 step 한정).
