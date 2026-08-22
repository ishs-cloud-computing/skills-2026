# Security 부착 KIT — IRSA · Pod Identity · OIDC

Pod에 IAM 권한을 주는 방식을 정하고 붙인다. Terraform 파일 복사가 없는 **판정 + 명령 KIT**이다.

## 이 KIT이 맞나 — 방식 판정을 먼저 한다

| 채점 스크립트가 보는 것 | 방식 |
| --- | --- |
| ServiceAccount의 `eks.amazonaws.com/role-arn` **annotation을 읽는다** | **IRSA** (`withOIDC: true` + `iam.serviceAccounts`) |
| Role의 존재·정책 내용만 읽는다 / Pod 안에서 API 호출이 되는지만 본다 | **Pod Identity** (기본값) |

과제지가 "OIDC"를 명시해도 판정은 같다 — OIDC provider는 IRSA의 전제 조건이다.

**Pod Identity는 annotation을 만들지 않는다.** annotation을 읽는 채점 항목이면 Pod Identity는 무조건 0점이다. 판정을 확정한 뒤에만 손을 댄다.

## 세트별 현재 방식

| 세트 | 클러스터 | 방식 | 앱 SA / 네임스페이스 |
| --- | --- | --- | --- |
| set-02 | `wskorea26-cluster` | **IRSA** (`withOIDC: true`) | `wskorea26-book-sa` / `wskorea26` |
| set-03 | `wsc2026-eks-cluster` | **Pod Identity** | `wsc2026-book-sa` / `wsc2026` |
| set-07 | `unicorn-eks-cluster` | **Pod Identity** | `unicorn-book-app-sa` / `unicorn` |

리전은 세 세트 모두 `ap-northeast-2`.

## CHANGE — 당일 고치는 값

Terraform 변수 없음. 아래 스니펫의 이름·네임스페이스를 과제지 값으로 직접 바꾼다. **Role 이름이 과제지에 명시되면 정확히 일치시킨다** — 채점 스크립트가 Role을 직접 읽는다.

## 1. IRSA — 신규 클러스터

```yaml
# 파일: set-XX/task-1/eksctl/cluster.yaml
iam:
  withOIDC: true                    # 없으면 eksctl 이 OIDC provider 부재로 실패한다
  serviceAccounts:
    - metadata:
        name: <SA이름>
        namespace: <네임스페이스>
      attachPolicyARNs:
        - "${POLICY_ARN}"           # ARN 그대로 주입. 문자열 재조립 금지
```

<details><summary><b>값 뽑기 — 세트별 (policy ARN)</b></summary>

| 세트 | policy 리소스 | output |
| --- | --- | --- |
| set-02 | `aws_iam_policy.book_app` · `.lbc` · `.fluent_bit` | `book_app_policy_arn` · `lbc_policy_arn` · `fluent_bit_policy_arn` (**이미 있음**) |
| set-03 | `aws_iam_policy.book_pod` · `.lbc` · `.fluentbit` · `.grafana` | **없음** — Pod Identity 구성이라 role ARN만 노출된다. 아래 블록 추가 |
| set-07 | `aws_iam_policy.lbc` (나머지는 inline `aws_iam_role_policy`) | **없음** — 아래 블록 추가 |

```hcl
# 파일: set-03/task-1/terraform/outputs.tf
output "policy_arns" {
  value = {
    book_pod  = aws_iam_policy.book_pod.arn
    lbc       = aws_iam_policy.lbc.arn
    fluentbit = aws_iam_policy.fluentbit.arn
    grafana   = aws_iam_policy.grafana.arn
  }
}

# 파일: set-07/task-1/terraform/outputs.tf
output "policy_arns" {
  value = { lbc = aws_iam_policy.lbc.arn }
}
```

```powershell
# set-02 — 그대로 env 로
$env:BOOK_APP_POLICY_ARN   = terraform output -raw book_app_policy_arn
$env:LBC_POLICY_ARN        = terraform output -raw lbc_policy_arn
$env:FLUENT_BIT_POLICY_ARN = terraform output -raw fluent_bit_policy_arn

# set-03 / set-07 — map 이라 -json 으로 꺼낸다
terraform output -json policy_arns
$env:POLICY_ARN = (terraform output -json policy_arns | ConvertFrom-Json).lbc
```

set-07처럼 정책이 inline(`aws_iam_role_policy`)이면 ARN이 없다 — IRSA로 가려면 관리형 정책(`aws_iam_policy`)으로 먼저 빼야 한다.
</details>

## 2. Pod Identity — 신규 클러스터

```yaml
# 파일: set-XX/task-1/eksctl/cluster.yaml
iam:
  podIdentityAssociations:
    - namespace: <네임스페이스>
      serviceAccountName: <SA이름>
      roleARN: "${ROLE_ARN}"        # trust principal = pods.eks.amazonaws.com
addons:
  - name: eks-pod-identity-agent    # 없으면 association 이 있어도 자격증명이 안 나온다
```

<details><summary><b>값 뽑기 — 세트별 (role ARN)</b></summary>

| 세트 | role 리소스 | output |
| --- | --- | --- |
| set-02 | 없음 (IRSA 구성) | — |
| set-03 | `aws_iam_role.book_pod` · `.lbc` · `.fluentbit` · `.grafana` | `pod_identity_role_arns` (map, **이미 있음**) |
| set-07 | `aws_iam_role.book_app` · `.fluentbit` · `.cwexporter` · `.lbc` · `.ebs_csi` | `pod_identity_role_arns` (map, **이미 있음**) |

```powershell
# map output 이므로 -json + ConvertFrom-Json
$roles = terraform output -json pod_identity_role_arns | ConvertFrom-Json

# set-03
$env:BOOK_POD_ROLE_ARN  = $roles.book_pod
$env:LBC_ROLE_ARN       = $roles.lbc
$env:FLUENTBIT_ROLE_ARN = $roles.fluentbit
$env:GRAFANA_ROLE_ARN   = $roles.grafana

# set-07
$env:BOOK_APP_ROLE_ARN   = $roles.book_app
$env:LBC_ROLE_ARN        = $roles.lbc
$env:FLUENTBIT_ROLE_ARN  = $roles.fluentbit
$env:CWEXPORTER_ROLE_ARN = $roles.cwexporter
```

set-02를 Pod Identity로 바꿔야 하면 role이 없다 — `aws_iam_policy.book_app` 을 붙일 role을 새로 만들고 아래 output을 추가한다:

```hcl
# 파일: set-02/task-1/terraform/outputs.tf
output "pod_identity_role_arns" {
  value = { book_app = aws_iam_role.book_app_pod.arn }
}
```
</details>

## 3. 이미 만든 클러스터에 당일 부착 (재생성 금지)

```powershell
# ---- IRSA ----
eksctl utils associate-iam-oidc-provider --cluster <클러스터> --region ap-northeast-2 --approve
eksctl create iamserviceaccount --cluster <클러스터> --region ap-northeast-2 `
  --namespace <ns> --name <sa> --attach-policy-arn $env:POLICY_ARN `
  --role-name <과제지_지정_Role_이름> --approve `
  --override-existing-serviceaccounts      # SA 가 이미 있을 때 필수

# ---- Pod Identity ----
eksctl create addon --cluster <클러스터> --region ap-northeast-2 --name eks-pod-identity-agent
eksctl create podidentityassociation --cluster <클러스터> --region ap-northeast-2 `
  --namespace <ns> --service-account-name <sa> --role-arn $env:ROLE_ARN
```

부착 후 **Pod를 재시작해야 자격증명이 주입된다**: `kubectl rollout restart deployment/<이름> -n <ns>`

<details><summary><b>값 뽑기 — 세트별 (그대로 붙여넣는 형태)</b></summary>

```powershell
# set-02 (IRSA)
eksctl create iamserviceaccount --cluster wskorea26-cluster --region ap-northeast-2 `
  --namespace wskorea26 --name wskorea26-book-sa `
  --attach-policy-arn (terraform output -raw book_app_policy_arn) `
  --approve --override-existing-serviceaccounts
kubectl rollout restart deployment -n wskorea26

# set-03 (Pod Identity)
$roles = terraform output -json pod_identity_role_arns | ConvertFrom-Json
eksctl create podidentityassociation --cluster wsc2026-eks-cluster --region ap-northeast-2 `
  --namespace wsc2026 --service-account-name wsc2026-book-sa --role-arn $roles.book_pod
kubectl rollout restart deployment -n wsc2026

# set-07 (Pod Identity)
$roles = terraform output -json pod_identity_role_arns | ConvertFrom-Json
eksctl create podidentityassociation --cluster unicorn-eks-cluster --region ap-northeast-2 `
  --namespace unicorn --service-account-name unicorn-book-app-sa --role-arn $roles.book_app
kubectl rollout restart deployment -n unicorn
```
</details>

## 4. Role·Policy는 Terraform에서 만든다

- Pod Identity trust: principal `pods.eks.amazonaws.com` + `sts:AssumeRole`·`sts:TagSession`. 본 클러스터 한정 조건까지 거는 패턴은 **set-07 task-1 `terraform/iam.tf`** 참고.
- IRSA trust(OIDC federated)는 `eksctl create iamserviceaccount` 가 만들어 준다. Terraform으로는 **policy만** 만들고 ARN을 넘기는 쪽이 빠르다. Role 이름까지 지정된 경우 `--role-name` 으로 준다.

<details><summary><b>값 뽑기 — 세트별 (클러스터 ARN·계정)</b></summary>

| 세트 | `cluster_arn` output | `account_id` output |
| --- | --- | --- |
| set-02 | **없음** — 아래 블록 추가 | 있음 |
| set-03 | 있음 | 있음 |
| set-07 | 있음 | 있음 |

```hcl
# 파일: set-02/task-1/terraform/outputs.tf
output "cluster_arn" { value = local.cluster_arn }
```

```powershell
terraform output -raw cluster_arn
terraform output -raw account_id
# OIDC provider URL (IRSA trust 의 sub 조건에 쓰인다)
aws eks describe-cluster --name <클러스터> --region ap-northeast-2 `
  --query "cluster.identity.oidc.issuer" --output text
```
</details>

## VERIFY

```powershell
# IRSA — annotation 존재 자체가 채점 형태
kubectl get sa <sa> -n <ns> -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'

# Pod Identity
aws eks list-pod-identity-associations --cluster-name <클러스터> --region ap-northeast-2

# 공통 — Pod 안에서 실제 신원 확인
kubectl exec deploy/<이름> -n <ns> -- aws sts get-caller-identity
```

## TROUBLESHOOT

- **Pod Identity로 "정정"하지 말 것.** annotation을 읽는 항목이면 0점이다. 방식 판정을 먼저 확정한다.
- `withOIDC: true` 없이 `iam.serviceAccounts` 만 넣으면 eksctl이 OIDC provider 부재로 실패한다. 기존 클러스터면 `eksctl utils associate-iam-oidc-provider` 를 먼저 돌린다.
- ServiceAccount가 이미 있으면 `eksctl create iamserviceaccount` 가 충돌한다 — `--override-existing-serviceaccounts`. **클러스터를 다시 만들지 않는다.**
- annotation을 붙여도 **이미 떠 있는 Pod에는 적용되지 않는다.** `kubectl rollout restart` 필수.
- Role 신뢰 정책의 `sub` 조건은 `system:serviceaccount:<namespace>:<sa-name>` 이 정확히 일치해야 한다. namespace를 틀리면 `AssumeRoleWithWebIdentity` 가 조용히 거부된다.
- `eks-pod-identity-agent` addon이 없으면 association이 있어도 Pod에 자격증명이 안 나온다.

---

절차 원본은 [KIT-INDEX 30분 루틴](../../../KIT-INDEX.md#30분-루틴), KIT을 두 개 이상 얹을 때는 [여러 KIT을 한꺼번에 얹을 때](../../../KIT-INDEX.md#여러-kit을-한꺼번에-얹을-때), 치환 자리 표기는 [코드 블록에서 바꿔야 하는 자리](../../../KIT-INDEX.md#코드-블록에서-바꿔야-하는-자리)를 본다. 여기 TROUBLESHOOT에 없는 실패는 [공통 트러블슈팅](../../TROUBLESHOOTING-COMMON.md).
