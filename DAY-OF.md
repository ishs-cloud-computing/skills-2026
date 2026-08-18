# DAY-OF — 대회장 실행 강령

과제지는 **종이로 배부된다.** 파일 대조(diff)는 불가능하고 눈으로 훑어야 한다.
재시동하면 파일이 초기화되고, AI 코딩 보조는 없으며(AWS 웹 Q 만 허용), 추가 시간도 없다.
이 문서는 그 상황에서 위에서 아래로 실행한다. 세트별 값은 각 `set-XX/task-Y/README.md` 의 **값 대조표**를 쓴다.

## 0. 도착 직후

**① 도구 설치 — [lab-bootstrap](https://github.com/ishs-cloud-computing/lab-bootstrap)** (Git·AWS CLI·SSM 플러그인·Helm·eksctl·kubectl·Terraform·k9s 일괄 설치)

```powershell
# 요구 사항: PowerShell 7 + Git (기본 Windows PowerShell 에서 실행)
winget install --id Microsoft.PowerShell -e --source winget --accept-package-agreements --accept-source-agreements
winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
```

```powershell
# 새 터미널에서 설치 실행
git clone https://github.com/ishs-cloud-computing/lab-bootstrap.git
cd lab-bootstrap
pwsh -ExecutionPolicy Bypass -File .\bootstrap.ps1
# GitHub 막히면 미러: git clone https://gitlab.com/ishs-cloud/lab-bootstrap.git
```

설치 후 **새 터미널을 연다** (PATH 반영). 재시동 시 파일이 초기화되므로 재부팅 때마다 다시 실행한다.

**② IAM 키 셋업** — SSO 대신 대회 당일 배부받는 IAM 사용자 액세스 키를 쓴다.

1. 배부받은 IAM 사용자로 콘솔 로그인 → 액세스 키 발급. 절차는 [IAM 액세스 키 발급 가이드](https://sungbin-park.tistory.com/142) 참고.
2. 본 PC에서 `aws configure` 로 발급받은 키를 등록한다 (Access Key ID / Secret / 리전 / 출력형식 `json`).
3. `aws sts get-caller-identity` 로 등록을 확인한다.

**③ 저장소 클론(② 와 병행)**

```powershell
git clone https://github.com/ishs-cloud-computing/skills-2026.git; cd skills-2026
```

- 세트 번호를 확인한다. 종이 과제지 표지·모듈 구성으로 판별한다.
- `.env.ps1`(본 PC)·`.env`(CloudShell) 를 재생성한다. 재부팅·CloudShell 세션 초기화 때마다 다시 만든다.
- CloudShell 접속을 **가장 먼저** 확인한다. 여기가 막히면 채점 경로 전체가 막힌다.
- 위 IAM 등록까지 끝난 뒤에 종이 과제지를 펼치고 1절로 넘어간다.

## 1. 종이 과제지 대조 — 형광펜 2색 (15분 이내)

**노랑 = 준비본과 값이 다름. 분홍 = 준비본에 없는 신규 문항.**

1. 해당 세트 README 의 **값 대조표**를 화면에 띄운다.
2. 종이 과제지를 위에서 아래로 읽으며 표와 1:1 대조한다.
3. 값이 다르면 종이에 **노랑**, 표에 없는 요구사항이면 **분홍**.
4. 채점지가 같이 배부되면 채점지도 같은 방식으로 훑는다. 안 주면 준비본 `mark.md` 기준으로 간다.

대조가 끝나면:

- **노랑** → `terraform.tfvars` 값 교체. 값 대조표에서 ⚠ 가 붙은 축은 tfvars 한 줄로 끝나지 않는다. 표의 "고칠 곳" 에 적힌 파일을 같이 고친다.
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
