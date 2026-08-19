# DAY-OF — 대회장 실행 강령

과제지는 **종이로 배부된다.** 파일 대조(diff)는 불가능하고 눈으로 훑어야 한다.
재시동하면 파일이 초기화되고, AI 코딩 보조는 없으며(AWS 웹 Q 만 허용), 추가 시간도 없다.
이 문서는 그 상황에서 위에서 아래로 실행한다. 세트별 값은 [7절 **값 대조표**](#7-값-대조표)를 쓴다.

런북 코드블록은 붙여넣기 전에 **한 줄씩 칠지 블록째 칠지 먼저 판단**한다 — 앞 명령의 출력·성공 여부에 뒤가 걸리는 블록(로그인·apply·삭제·롤아웃)은 한 줄씩, 단순 설치·조회는 블록째. PowerShell 은 앞 줄이 실패해도 뒤 줄을 계속 실행한다.

## 0. 도착 직후

①~④ 는 직렬이 아니다. `bootstrap.ps1` 이 도는 동안 손이 비므로 **두 트랙으로 병행**한다.

| 터미널 트랙 | 브라우저 트랙 (bootstrap 도는 동안) |
| --- | --- |
| ① winget → `bootstrap.ps1` 실행 | ② 콘솔 로그인 → 액세스 키 발급 |
| ③ 저장소 클론 (Git 은 ① 초반에 이미 설치됨) | ④ CloudShell 탭 그룹 · 즐겨찾기 세팅 |

합류점: `aws configure` 는 ①(AWS CLI 설치)과 ②(키 발급)가 **둘 다 끝난 뒤** 새 터미널에서 한다.

**① 도구 설치 — [lab-bootstrap](https://github.com/ishs-cloud-computing/lab-bootstrap)** (Git·AWS CLI·SSM 플러그인·Helm·eksctl·kubectl·Terraform·k9s 일괄 설치)

```powershell
# 요구 사항: PowerShell 7 + Git (기본 Windows PowerShell 에서 실행)
winget install --id Microsoft.PowerShell -e --source winget --accept-package-agreements --accept-source-agreements
winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements

# 스크립트 차단 해제 (기본 Restricted 는 프로필 스크립트도 막음) + 새 탭이 자동으로 pwsh 로 넘어가도록 프로필 수정
Set-ExecutionPolicy Bypass -Scope CurrentUser -Force
New-Item -ItemType Directory -Force (Split-Path $PROFILE) | Out-Null
Add-Content $PROFILE 'if (Get-Command pwsh -ErrorAction SilentlyContinue) { pwsh -ExecutionPolicy Bypass; exit }'
```

```powershell
# 새 탭 열면 프로필이 pwsh 로 전환됨 — 그 탭에서 설치 실행
git clone https://github.com/ishs-cloud-computing/lab-bootstrap.git
cd lab-bootstrap
pwsh -ExecutionPolicy Bypass -File .\bootstrap.ps1
# GitHub 막히면 미러: git clone https://gitlab.com/ishs-cloud/lab-bootstrap.git
```

설치 후 **새 터미널을 연다** (PATH 반영). 재시동 시 파일이 초기화되므로 재부팅 때마다 다시 실행한다.

**② IAM 키 셋업** — SSO 대신 대회 당일 배부받는 IAM 사용자 액세스 키를 쓴다. 발급은 브라우저만 있으면 되므로 bootstrap 이 도는 동안 한다.

1. 배부받은 IAM 사용자로 콘솔 로그인 → 액세스 키 발급. 절차는 [IAM 액세스 키 발급 가이드](https://sungbin-park.tistory.com/142) 참고.
2. (① 완료 후) 본 PC에서 `aws configure` 로 발급받은 키를 등록한다 (Access Key ID / Secret / 리전 / 출력형식 `json`).
3. `aws sts get-caller-identity` 로 등록을 확인한다.

**③ 저장소 클론(bootstrap 과 병행 — Git 은 ① 초반에 이미 설치됨)**

```powershell
git clone https://github.com/ishs-cloud-computing/skills-2026.git; cd skills-2026
```

- 세트 번호를 확인한다. 종이 과제지 표지·모듈 구성으로 판별한다.
- `.env.ps1`(본 PC)·`.env`(CloudShell) 를 재생성한다. 재부팅·CloudShell 세션 초기화 때마다 다시 만든다.
- CloudShell 접속을 **가장 먼저** 확인한다. 여기가 막히면 채점 경로 전체가 막힌다.

**④ 브라우저 작업공간 — 모듈별 CloudShell 탭 그룹 (② 에 이어 브라우저 트랙에서)**

2과제는 모듈마다 리전이 다르다. 리전을 착각한 탭에서 명령을 치는 사고를 탭 그룹 번호로 막는다.

1. 모듈별 리전의 CloudShell 을 각각 새 탭으로 연다 (`<리전>.console.aws.amazon.com/cloudshell/home?region=<리전>`).
2. 탭 우클릭 → **그룹에 탭 추가** → **새 그룹** → 그룹 이름을 모듈 번호(`1`~`4`)로 붙인다. 색은 모듈마다 다르게.

   ![탭 우클릭 메뉴에서 그룹에 탭 추가 → 새 그룹, 모듈 번호 1~4로 색 구분](shared/asset/tab-group-cloudshell.png)

   같은 조작은 CloudShell 탭이 아닌 일반 탭에서도 동일하다.

   ![Chrome 탭 우클릭 메뉴의 새 그룹에 탭 추가](shared/asset/tab-group-chrome-menu.png)

3. 이후 그 모듈 작업·채점은 반드시 해당 번호 그룹의 탭에서만 한다. 탭을 새로 열면 같은 그룹에 넣는다.
4. 콘솔 상단 즐겨찾기 바에 자주 쓰는 서비스(VPC·EC2·S3·IAM·RDS·CloudFormation·Secrets Manager·CloudWatch·ECR·WAF·EKS)를 별표로 고정한다. 검색 왕복을 줄인다.
5. **1과제는 VPC apply 가 끝나는 대로 그 리전 CloudShell 에 VPC environment 를 무조건 만든다** — 프라이빗 리소스(RDS·EKS 프라이빗 엔드포인트) 접근용. bastion 대체라 불필요 EC2 감점을 피한다. 생성: CloudShell 좌측 **+** → **Create VPC environment** → VPC·프라이빗 서브넷·SG 선택. 프라이빗 서브넷이 NAT 를 못 타면 AWS API 호출도 안 나가니 라우팅을 먼저 확인한다.

- 위 IAM 등록까지 끝난 뒤에 종이 과제지를 펼치고 1절로 넘어간다.

## 1. 종이 과제지 대조 — 형광펜 2색 (15분 이내)

**노랑 = 준비본과 값이 다름. 분홍 = 준비본에 없는 신규 문항.**

1. [7절 **값 대조표**](#7-값-대조표)에서 해당 세트 표를 화면에 띄운다.
2. 종이 과제지를 위에서 아래로 읽으며 표와 1:1 대조한다.
3. 값이 다르면 종이에 **노랑**, 표에 없는 요구사항이면 **분홍**.
4. 채점지가 같이 배부되면 채점지도 같은 방식으로 훑는다. 안 주면 준비본 `mark.md` 기준으로 간다.

대조가 끝나면:

- **노랑** → `terraform.tfvars` 값 교체. 값 대조표에서 ⚠ 가 붙은 축은 tfvars 한 줄로 끝나지 않는다. 표의 "고칠 곳" 에 적힌 파일을 같이 고친다.
- 리전·prefix 처럼 여러 파일에 흩어진 값은 VS Code 전체 치환으로 잡는다: `code set-XX` 로 열고 **Ctrl+Shift+H**(치환) 또는 **Ctrl+Shift+F**(검색만) → 결과 목록에서 바꾸면 안 되는 라인은 hover 후 **X 로 제외**, 라인별 치환 아이콘으로 개별 적용도 가능 → 남은 것 일괄 치환.
- **일괄 치환에서 반드시 빼야 하는 것** — 치환 전 결과 목록을 훑으며 제외(X)한다:
  - `provided/`·`task.md`·`mark.md`·채점 스크립트(`mark*.sh`) — 대회 제공 원본이자 대조 기준. 여기가 바뀌면 "준비본과 뭐가 다른가" 판단 자체가 무너진다. **files to exclude** 에 `**/provided/**, **/task.md, **/mark*` 를 넣으면 안전.
  - `NOTES.md` 결정 로그·정정 로그 — 과거 기록이라 값이 옛날 것이어도 그대로 둔다.
  - `*.tfstate`·`outputs.json` — 배포 산출물. 치환해도 실제 리소스와 어긋나기만 한다.
  - **짧은 접두어는 부분 문자열 오염 주의** (예: `wsc` 치환이 `wsc2026` 도 침) — **Match Whole Word(Alt+W)** 켜거나 결과 미리보기로 판별. 반대로 리전처럼 AZ 접미(`ap-northeast-2a`)까지 같이 바뀌어야 하는 값은 Whole Word 를 끄고 잡는다.
- **분홍** → 별도 목록으로 빼서 2절로 넘긴다. **기존 문항·기존 모듈은 건드리지 않는다.**

당일 변동은 기존 문제 교체가 아니라 **문항 추가**다. 기존 4모듈을 재작성하려 들면 시간이 날아간다.

## 2. 신규 문항(분홍)은 출제가이드 카탈로그 안에서 나온다

출제자는 자유롭게 문제를 만들지 않는다. 2과제 출제지침은 **모듈 카탈로그 13개**를 고정하고
"제공된 모듈 중 4개를 골라 출제한다" 고 못박는다. 1과제는 **작업범위 12개** 중 선택이다.
따라서 분홍 항목을 카탈로그 번호에 매핑하면 어디서 코드를 가져올지가 바로 나온다.

### 2과제 모듈 카탈로그 13개


| #  | 모듈                     | 필수 서비스                          | 구현 있는 세트                  |
| -- | ------------------------ | ------------------------------------ | ------------------------------- |
| 1  | NoSQL                    | DynamoDB or DocumentDB               | set-07 m1, set-08 m1            |
| 2  | CDN                      | CloudFront                           | set-07 m2                       |
| 3  | EKS Scaling              | EKS                                  | set-05 m1, set-07 m3, set-08 m4 |
| 4  | Real-time data analytics | VPC, EC2, ELB, Managed Flink         | set-02 m2                       |
| 5  | VPC Lattice              | VPC                                  | set-05 m2, set-08 m2            |
| 6  | Workflow                 | S3, Lambda, DynamoDB, Step Functions | set-02 m1                       |
| 7  | Cloud event handling     | VPC, EC2                             | set-02 m3, set-08 m3            |
| 8  | RDS Connection           | RDS, VPC                             | **없음**                        |
| 9  | VPN                      | Client VPN, VPC, EC2                 | **없음**                        |
| 10 | Keycloak                 | VPC, EC2, IAM, Keycloak              | **없음**                        |
| 11 | Container logging        | VPC, Loki, Grafana, EKS, EC2         | set-05 m3, set-07 m4            |
| 12 | REST API Implement       | Lambda                               | set-05 m4                       |
| 13 | MSK                      | MSK, VPC                             | set-02 m4                       |

- 구현이 있는 모듈이면 **그 세트 디렉토리를 통째로 복사**하고 이름·리전만 교체한다. 처음부터 쓰지 않는다.
- 8·9·10 은 어느 세트에도 없다. 이게 걸리면 맨몸이므로 **시간을 여기에 먼저 배분**한다.

### 1과제 추가 문항

필수 7개(VPC·Container·Database·Static hosting·ECR·로드밸런서·Application)는 이미 다 들어가 있다.
추가분은 **아직 안 쓰인 옵션 5개**에서 나온다 — KMS / WAF / Security(IAM·Pod Identity·IRSA·OIDC) / Lambda GET API / Observability.
출제지침이 "모니터링 도구 설치" 류를 예시로 들므로 Observability 가 가장 유력하다.

옵션 5개는 전부 **[`shared/addons/`](shared/addons/README.md) 부착 키트**로 대응한다 —
스니펫 복사 → tfvars 값 주입 → plan 으로 기존 diff 없음 확인 → apply. 기존 문항은 건드리지 않는다.

| 옵션 | 부착 키트 | 비고 |
| --- | --- | --- |
| KMS | `shared/addons/kms/` | RDS·EBS·ECR·EKS 는 생성 후 암호화 변경 불가 — 대상 판별 먼저 |
| WAF | `shared/addons/waf/` | ALB 는 regional, CloudFront 는 us-east-1 alias 필수 |
| Security | `shared/addons/irsa/` | 채점이 role-arn annotation 읽으면 IRSA, 아니면 Pod Identity |
| Lambda GET API | set-07 task-1 `lambda.tf` 복사 | set-05 task-2 module-4 (REST API) 도 참고 |
| Observability | `shared/addons/observability/` | Container Insights 는 addon 한 줄, 도구형은 set-07 monitoring 복사 |

금지선을 넘는 요구는 오독이다. 1과제에는 **인프라 스케일링 문제가 출제되지 않고**, 3rd-party Addon(Istio·Cilium·Calico·Crossplane·Nginx)은 불가하며, Helm 은 채점요소가 될 수 없다.

## 3. 모듈 5·6 추가

```powershell
Copy-Item -Recurse _template/task-2/module-4 set-XX/task-2/module-5-<name>
New-Item -ItemType Directory set-XX/task-2/provided/module-5
```

- `_template/task-2/module-1~4` 는 내용이 같은 빈 스켈레톤이다. 어느 걸 복사해도 결과는 같다.
- **세트의 구현된 module-4 를 복사하지 않는다.** 지워야 할 잔재가 딸려와 더 느리다.
- 모듈 간 **리전이 겹치면 안 된다**. 리소스도 공유하면 안 된다.
- 6모듈이면 배점이 모듈당 7.5 → **5.0** 으로 재조정된다. 채점 항목 우선순위를 다시 잡는다.

## 4. 당일 배부 바이너리·앱 교체

배부물은 `provided/` 규칙과 같이 **원본 그대로** 둔다. 구현 코드가 그걸 참조하게 만든다.

```powershell
# 1. 배부물을 원본 위치에 둔다 (수정 금지)
Copy-Item -Recurse <배부경로>/* shared/provided/task-1/     # task-1
Copy-Item -Recurse <배부경로>/* set-XX/task-2/provided/module-N/   # task-2

# 2. 빌드 컨텍스트가 그 경로를 가리키는지 확인한다
Select-String -Path set-XX/task-1/README.md -Pattern "docker build"

# 3. 이미지 재빌드·푸시 (x86_64 고정)
$ECR = terraform -chdir=set-XX/task-1/terraform output -raw ecr_repository_url
aws ecr get-login-password --region <리전> | docker login --username AWS --password-stdin ($ECR -split '/')[0]
docker build --platform linux/amd64 -f app/Dockerfile -t "${ECR}:v2" <빌드컨텍스트>
docker push "${ECR}:v2"
```

- 로컬에 Docker 가 없으면 build/push 는 **CloudShell 필수 경로**다. 0단계에서 확인해 둔 접속을 쓴다.
- 롤아웃: ECS 는 `aws ecs update-service --force-new-deployment`, EKS 는 `kubectl rollout restart deployment/<이름>`.
- 롤백: 이전 태그로 `kubectl set image` 또는 태스크 정의 이전 리비전으로 되돌린다. **이전 태그를 지우지 않는다.**
- 앱이 바뀌면 앱 문자열에 의존하는 구성도 같이 바뀐다 — 로그 쿼리 필터, WAF 경로 regex, 헬스체크 경로.

## 5. 미완성 코드 완성 — Amazon Q 컨텍스트 템플릿

출제지침이 1·2과제 양쪽에 명시한다: **Kiro·Q-CLI·MCP 전부 불가. AWS 웹에서 사용 가능한 Q 만 허용.**
따라서 컨텍스트를 손으로 붙여넣어야 한다. 코드 전문을 넣지 말고 아래 4블록만 넣는다.

````text
아래 Python 파일의 TODO 를 채워라. 함수 시그니처와 기존 코드는 바꾸지 마라.
완성된 함수 본문만 출력하고 설명은 붙이지 마라.

# 1) 파일 상단 — import 와 상수 (그대로)
<import 문과 전역 상수 전문을 붙여넣는다. 환경변수 키 이름이 여기 있다>

# 2) 완성할 함수 스켈레톤
<def 시그니처와 docstring, # TODO 주석을 그대로 붙여넣는다>

# 3) 요구사항 명세
<과제지의 해당 문항 전문. 입력·출력 형식, 상태 코드, 에러 처리 규칙을 빠뜨리지 않는다>

# 4) 제약
- 표준 라이브러리와 boto3 만 사용
- 상수는 위 1)에 선언된 것만 사용하고 새 전역을 만들지 않는다
- 예외는 <명세에 적힌 형식> 으로 반환
````

- 요구사항 명세 블록이 가장 중요하다. 여기가 부실하면 그럴듯하지만 채점에 안 걸리는 코드가 나온다.
- 나온 코드는 **환경변수 키 이름·핸들러 경로·응답 필드명**을 배부 명세와 직접 대조한다. 이 셋이 틀리면 동작해도 0점이다.
- 로컬에서 한 번 실행해 확인한 뒤 배포한다.

## 6. 채점 직전

- EKS: **일반 CloudShell** 에서 `aws eks update-kubeconfig --name <클러스터> --region <리전>` **한 줄 뒤** `kubectl get nodes` 가 되는지 확인한다. 채점 중 허용되는 명령은 그 한 줄뿐이다.
- 채점 스크립트는 CloudShell 업로드 후 CRLF 를 제거한다: `sed -i 's/\r$//' <파일>`
- 과제지가 요구하지 않은 리소스를 지운다. 특히 **작업용 bastion** — 불필요 리소스는 감점이고, 3과제는 EC2 수가 적을수록 고득점이다.
- bastion 을 지우기 전에 CloudShell 경로를 **먼저 검증**한다. 지운 뒤에 권한이 없다는 걸 알면 손쓸 방법이 없다.
- 채점 중에는 리소스를 새로 만들거나 시작할 수 없다. 채점 때 쓸 것은 그 시점에 이미 running 이어야 한다.

## 7. 값 대조표

1절 종이 대조에서 쓰는 표. 각 세트 README 에는 여기로 오는 링크만 남겼다.
**set-05(task-1·2)·set-08 task-1·set-09 task-1 은 대조표 미작성** — 해당 세트가 걸리면 그 README 의 변수 목록(`variables.tf`)으로 직접 대조한다.

### task-1

#### set-02

| 축 | 준비본 값 | 다르면 고칠 곳 |
|---|---|---|
| 리전 | `ap-northeast-2` | `terraform/terraform.tfvars: region` |
| 비번호 | `<비번호>` | `terraform.tfvars: player_number` |
| VPC 이름·CIDR | `wskorea26-vpc` · `172.16.0.0/16` | `terraform.tfvars: vpc_cidr` / `variables.tf: vpc_name` |
| EKS 클러스터 | `wskorea26-cluster` (네임스페이스 `wskorea26`) | `terraform.tfvars: cluster_name` ⚠ |
| DynamoDB 테이블 | `wskorea26-data-table` | `terraform.tfvars: table_name` |
| ECR | `wskorea26-book-repo` | `variables.tf: ecr_repo_name` |
| Lambda | `wskorea26-book-lambda` · `python3.14` | `variables.tf: lambda_function_name`·`lambda_runtime` |
| S3 버킷 | `wskorea26-concert-bucket-<비번호>` | `variables.tf: bucket_name_prefix` |
| CloudFront | `wskorea26-concert-cf` · 헤더 `X-Origin-Verify` | `variables.tf: cloudfront_name`·`origin_verify_header` |
| ALB | `wskorea26-book-alb` / `wskorea26-grafana-alb` | `variables.tf: book_alb_name`·`grafana_alb_name` |
| 포트 | app `8080` / grafana `3000` | `variables.tf: container_port`·`grafana_port` |
| 로그 그룹 | `/wskorea26/eks/pod-logs` | `variables.tf: pod_log_group_name` |

⚠ **이름 접두어 `wskorea26` 는 tfvars 한 줄로 안 끝난다.** `eksctl/cluster.yaml` 과 `k8s/**` 전부에 리터럴로 박혀 있다. 접두어가 바뀌면 두 디렉토리를 전부 치환한다.

#### set-03

| 축 | 준비본 값 | 다르면 고칠 곳 |
|---|---|---|
| 리전 | `ap-northeast-2` | `terraform/variables.tf: region` |
| 이름 접두어 | `wsc2026` | `variables.tf: name_prefix` ⚠ |
| 비번호·버킷 접미 | `<비번호>` · `bucket_suffix` | `terraform.tfvars: player_number`·`bucket_suffix` |
| EKS 클러스터 | `wsc2026-eks-cluster` · `1.35` | `variables.tf: cluster_name`·`cluster_version` |
| VPC 이름·CIDR | `wsc2026-skills-vpc` · `192.168.0.0/16` | `variables.tf: vpc_name`·`vpc_cidr` |
| DynamoDB 테이블 | `wsc2026-book-table` | `variables.tf: table_name` |
| ECR | `wsc2026-book-ecr` | `variables.tf: ecr_name` |
| Lambda | `wsc2026-book-get-function` | `variables.tf: lambda_function_name` |
| CDN 사용 | `false` | `variables.tf: enable_cdn` |
| bastion | `true` · `t3.small` | `variables.tf: enable_bastion`·`bastion_instance_type` |

⚠ **접두어가 바뀌면 `name_prefix` 만으로 안 끝난다** (NOTES.md 참조). 서브넷 맵의 **키가 리터럴** `wsc2026-...` 이고, `eksctl/cluster.yaml`·`k8s/**` 도 전부 리터럴이다.

#### set-07

| 축 | 준비본 값 | 다르면 고칠 곳 |
|---|---|---|
| 리전 | `ap-northeast-2` (CloudFront·WAF·KMS 레플리카는 `us-east-1`) | `terraform/variables.tf: region` |
| 비번호 | `<비번호>` | `variables.tf: player_number` |
| EKS 클러스터 | `unicorn-eks-cluster` · `1.35` | `variables.tf: cluster_name`·`cluster_version` |
| VPC CIDR | `10.97.0.0/16` | `variables.tf: vpc_cidr` |
| 서브넷 이름 | `unicorn-subnet-{pub,priv}-{a,b,c}` (AZ별 1개, 총 6개) | `variables.tf: subnets` |
| 노드 타입 | `t3.medium` | `variables.tf: node_instance_type` |
| 감사 Role External ID | `unicorn-audit-2026` | `variables.tf: audit_external_id_prefix` |
| Grafana 관리자 | 빈 값(주입) | `variables.tf: grafana_admin_user`·`grafana_admin_password` |
| WAF XSS 룰 | `variables.tf: waf_xss_rules` 목록 | 문항이 추가되면 이 목록에 추가 |

⚠ **이름 접두어 `unicorn` 은 tfvars 밖에도 있다.** `eksctl/cluster.yaml` 과 `k8s/**` 에 리터럴로 박혀 있으니 접두어가 바뀌면 같이 친다. IAM Role 이름은 과제지 지정값과 **정확히** 일치해야 한다.

### task-2

#### set-02

| 모듈 | 리전 | 준비본 이름·값 | CIDR |
|---|---|---|---|
| module-1-workflow | `ap-southeast-1` | 버킷 `wsc2026-student-score-bucket-<비번호>` / 테이블 `wsc2026-student-score` / 함수 `wsc2026-student-score-function`·`-trigger` / 상태머신 `wsc2026-student-score-workflow` / `python3.12` | — |
| module-2-analytics | `ap-northeast-2` | `analytics-vpc` / EC2 `wsc2026-analytics-ec2`(`t3.small`, 앱 포트 `5000`) / ALB `wsc2026-analytics-alb` / 스트림 `wsc2026-order-stream` / Flink `wsc2026-analytics-flink`(`ZEPPELIN-FLINK-3_0`) / Glue `wsc2026_analytics_db` | `10.20.0.0/16` |
| module-3-event | `eu-west-1` | `event-vpc` / EC2 `wsc2026-event-ec2`(`t3.micro`) / SG `wsc2026-event-sg` / Trail `wsc2026-event-trail` / SNS `wsc2026-event-alert` / Config 룰 `wsc2026-sg-ssh-rule`·`wsc2026-required-tags-rule` / 필수 태그 키 `Project` | `172.16.0.0/16` |
| module-4-msk | `ap-northeast-1` | `msk-vpc` / MSK `wsc2026-msk-cluster`(Kafka `3.6.0`, `kafka.t3.small`) / Producer `wsc2026-sensor-producer` / 테이블 `wsc2026-sensor-data` / 함수 `wsc2026-sensor-consumer`·`-alert-consumer` | `192.168.0.0/16` |

각 모듈 `terraform/terraform.tfvars` 의 `player_number` 를 본인 비번호로 바꾼다.

⚠ **module-4 producer 인증 모드는 tfvars 가 아니라 당일 판정 대상이다.** 지급 바이너리가 IAM 인증을 못 하면 `terraform apply -var "producer_auth_mode=tls"` 로 내려간다 (`module-4-msk/select-auth-mode.ps1`).

#### set-07

| 모듈 | 리전 | 준비본 이름·값 | CIDR |
|---|---|---|---|
| module-1-nosql | `ap-southeast-1` | 테이블 `bigbae-nosql-reservation-table`·`bigbae-nosql-audit-table` / GSI `gsi-user-reservations` / Lambda `bigbae-nosql-reservation-audit` / EC2 `bigbae-nosql-app-ec2`(`t3.small`) | `10.0.0.0/16` (서브넷 `10.0.0.0/24`) |
| module-2-cdn-function | `us-east-1` | 버킷 접두 `skillsphone-landing-ab-` / KVS `skillsphone-cdn-ab-config` / Function `-req-fn`·`-res-fn` / 배포 `skillsphone-cdn-ab-distribution` / 쿠키 `x-sp-ab` / 가중치 `0.3` / 경로 `/version-a/index.html`·`/version-b/index.html` | — |
| module-3-eks-scaling | `ap-northeast-2` | 클러스터 `skm-eks-cluster` / SQS `skm-order-queue` / ECR `skm-order-processor` / 접두 `skm-eks` | `10.13.0.0/16` |
| module-4-container-logging | `ap-northeast-1` | 클러스터 `o11y-cluster` / ECR `o11y-log-generator` / ALB `o11y-app-alb`·`o11y-grafana-alb` / 포트 `8080`·`3000` / 헬스 `/healthz`·`/api/health` | `10.14.0.0/16` |

⚠ **module-2**: 쿠키명·헤더명·KVS 키명이 CloudFront Function 의 **JS 안 리터럴**이라 변수화돼 있지 않다. 이름이 바뀌면 함수 코드를 직접 고친다.

⚠ **module-4**: Grafana 패널의 Loki 라인 필터 `"log generated"` 는 **지급 `app.py` 의 msg 리터럴**이다. 당일 앱이 바뀌어 msg 가 달라지면 필터도 같이 고친다.

#### set-08

| 모듈 | 리전 | 준비본 이름·값 | CIDR |
|---|---|---|---|
| module-1-nosql | `ap-northeast-2` (`2a`) | VPC `skills-nosql-vpc` / DocDB 클러스터 `skills-nosql-docdb-cluster`·인스턴스 `skills-nosql-docdb-instance-1`(`db.t3.medium`, 포트 `27017`, 백업 `1`일) / Secret `skills-nosql-docdb-secret` / KMS `alias/skills-nosql-docdb` / EC2 `skills-nosql-client-ec2`(`t3.micro`, 앱 `8080`) | `10.63.0.0/16` |
| module-2-lattice | `ap-northeast-1` (`1a`) | Client VPC `skills-lattice-client-vpc` / Service VPC `skills-lattice-service-vpc` / EC2 `skills-lattice-client-ec2`·`skills-lattice-service-ec2` / SN `skills-lattice-sn` / Service `skills-lattice-order-service` / TG `skills-lattice-order-tg` / Listener `skills-lattice-http-listener`(`80` → `8080`) | client `10.61.0.0/16` · service `10.62.0.0/16` |
| module-3-event-handling | `ap-southeast-1` (`1a`) | VPC `skills-ceh-vpc` / EC2 `skills-ceh-ec2`(`t3.micro`) / 보호 SG `skills-ceh-protected-sg` / SNS `skills-ceh-alert-topic` / Lambda `skills-ceh-remediate-fn`(timeout `30`) / Trail `skills-ceh-cloudtrail` / 룰 `skills-ceh-sg-change-rule` | `10.73.0.0/16` |
| module-4-sqs-scaling | `us-west-2` | 클러스터 `skills-sqs-cluster` / SQS `skills-sqs-queue`(visibility `30`) / ECR `skills-sqs-worker` / 접두 `skills-sqs` | `10.64.0.0/16` |

4모듈 모두 `terraform.tfvars` 가 비어 있고 기본값이 과제지 값이다. **다른 값만 tfvars 에 적어 덮는다.**

⚠ **module-4 `cluster_name` 을 바꾸면 tfvars 로 안 끝난다.** `k8s/10-karpenter-nodepool.yaml` 의 `subnetSelectorTerms`(`karpenter.sh/discovery`)·`securityGroupSelectorTerms`(`aws:eks:cluster-name`) 태그 값과 `eksctl/cluster.yaml` 의 정책 ARN·accessEntry, EC2NodeClass `role` 이 이름을 리터럴로 재조립한다. 놓치면 Karpenter 가 서브넷·SG 를 못 찾아 노드 프로비저닝이 조용히 실패한다.

⚠ **module-2 service SG 에 CIDR 을 절대 추가하지 않는다.** 과제지가 `0.0.0.0/0` 허용 시 미충족을 명시한다.

### task-3

| 축 | 준비본 값 | 다르면 고칠 곳 |
|---|---|---|
| 이름 접두어 | `skills` | `terraform/terraform.tfvars: prefix` ⚠ |
| S3 버킷 | `wsc2026-task3-images-<비번호>` (전역 유일) | `terraform.tfvars: bucket_name` |
| RDS 식별자 | `apdev-rds-instance` | `terraform.tfvars: db_identifier` |
| DB 비밀번호 | 주입값 | `terraform.tfvars: db_password` |
| WAF 보호 경로 | `/v1/user`·`/v1/product`·`/v1/stress`·`/images/*` regex | `terraform.tfvars: waf_api_path_regexes` |
| 스캐너 UA 목록 | 저장소에 없음 — 당일 WAF 콘솔에서 직접 편집 | task-3 README STEP 12 |

⚠ **`prefix` 한 줄이 모든 리소스 이름을 바꾸지만 코드 전체를 바꾸지는 않는다.** `eksctl/cluster.yaml`·`k8s/00-nodeclass.yaml`·`k8s/20-ingress.yaml`·`scripts/*.sh` 의 클러스터·ALB 이름을 같이 고친다.

⚠ **로그 쿼리의 정상 경로 목록 `<NORMAL_PATHS>` 는 regex 리터럴이라 파라미터화가 안 된다.** 당일 앱 경로가 바뀌면 쿼리 본문을 손으로 치환한다.
