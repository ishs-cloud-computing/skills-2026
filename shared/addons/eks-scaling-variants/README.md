# EKS 스케일링 부착 KIT — Karpenter · KEDA · Fargate

노드/파드 자동 확장 변형 모음.

## 이 KIT이 맞나

- **1과제(task-1)에는 인프라 스케일링 문항이 출제되지 않는다** (출제지침). 과제지에서 보이면 **오독을 먼저 의심**한다.
- 2과제 EKS Scaling 모듈(카탈로그 #3)이면 맞다.
- **노드 강화·로깅** → [eks-logging-variants](../eks-logging-variants/README.md).

## 세트별 클러스터 정보 (부착 대상)

| | set-02 | set-03 | set-07 |
| --- | --- | --- | --- |
| task-1 클러스터 | `wskorea26-cluster` | `wsc2026-eks-cluster` | `unicorn-eks-cluster` |
| NG 구성 | addon / app 2개 (MNG) | Addon / Workload 2개 (MNG) | `unicorn-app-ng` / addon (MNG) |
| Karpenter | **없음** | **없음** | **없음** (task-1) |
| KEDA | **없음** | **없음** | **없음** |
| Fargate | **없음** | **없음** | **없음** |
| 스케일링 구현 원본 | — | — | **set-07 task-2 module-3-eks-scaling** |

task-1 세 세트 모두 관리형 노드그룹만 쓴다. 스케일링 요구가 실제로 오면 **set-07 task-2 module-3** 을 복사하는 쪽이 이 KIT보다 빠르다.

## 복사할 파일

| 원본 | 내용 |
| --- | --- |
| `k8s/10-karpenter-nodepool.yaml` | EC2NodeClass + NodePool 전체 옵션 (taint·label·spot·instance-type·expireAfter·limits·disruption·budgets·blockDeviceMappings·metadataOptions) |
| `k8s/30-keda-scaledobject.yaml` | TriggerAuthentication(`podIdentity.provider: aws`) + ScaledObject 풀옵션 |
| `eksctl/fargate-profile.yaml` | Fargate profile 3개 (keda·karpenter·kube-system) |
| `eksctl/addon-nodegroup.yaml` | `CriticalAddonsOnly` taint 붙은 Addon 관리형 NG |
| `terraform/karpenter-interruption.tf` · `variables.tf` | interruption SQS 큐 + EventBridge 룰 4종 + 컨트롤러 정책 |

## CHANGE — 당일 고치는 값

| 변수 | 기본값 | 무엇 |
| --- | --- | --- |
| `addon_ekscale_cluster_name` | **필수** | 클러스터 이름. interruption 큐 이름 기본값이자 helm `settings.clusterName` |
| `addon_ekscale_queue_name` | `""` | 비우면 클러스터 이름을 쓴다 (공식 CloudFormation 관례). helm `settings.interruptionQueue` 와 **정확 일치** |
| `addon_ekscale_karpenter_role_name` | `""` | Karpenter 컨트롤러 IAM Role 이름. 비우면 정책만 만들고 attach하지 않는다 |

## CHECK · RUN

```powershell
aws sts get-caller-identity; aws configure get region
kubectl config current-context
terraform fmt; terraform init; terraform validate; terraform plan; terraform apply
```

## 1. Karpenter NodePool + EC2NodeClass

```yaml
# 파일: set-XX/task-2/module-N/k8s/10-karpenter-nodepool.yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]      # spot 우선, 미가용 시 on-demand
        - key: node.kubernetes.io/instance-type
          operator: In
          values: ["t3.medium", "t3.large"]
  limits:
    cpu: "16"
    memory: 64Gi
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    budgets:
      - nodes: "10%"
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

`${CLUSTER_NAME}`·`${NODE_ROLE_NAME}` 을 치환해 apply한다:

```powershell
$c = Get-Content k8s/10-karpenter-nodepool.yaml -Raw
$c = $c.Replace('${CLUSTER_NAME}', (terraform output -raw cluster_name)) `
       .Replace('${NODE_ROLE_NAME}', (terraform output -raw karpenter_node_role_name))
$c | kubectl apply -f -

kubectl get nodepool,ec2nodeclass -o wide
kubectl get nodes -L karpenter.sh/capacity-type,node.kubernetes.io/instance-type
```

```hcl
# 파일: set-XX/task-2/module-N/terraform/outputs.tf
output "cluster_name"             { value = var.cluster_name }
output "karpenter_node_role_name" { value = aws_iam_role.karpenter_node.name }
```

task-1 세 세트에는 Karpenter가 없다 — 클러스터 이름만 참고용:

```powershell
# set-02 / set-03 / set-07 — cluster_arn 에서 잘라 쓴다 (set-02 는 cluster_arn output 도 없다)
(terraform output -raw cluster_arn).Split('/')[-1]
```

spot을 쓰려면 계정에 서비스 연결 역할이 있어야 한다:

```powershell
aws iam create-service-linked-role --aws-service-name spot.amazonaws.com   # 이미 있으면 에러 무시
```

**Karpenter가 띄운 노드의 역할은 eksctl이 access entry를 자동으로 만들지 않는다** — `accessConfig.accessEntries` 에 `EC2_LINUX` 로 등록하지 않으면 노드가 NotReady다.
</details>

## 2. KEDA ScaledObject

```yaml
# 파일: set-XX/task-2/module-N/k8s/30-keda-scaledobject.yaml
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: aws-creds
  namespace: ${NAMESPACE}
spec:
  podIdentity:
    provider: aws          # 채점지가 aws-eks 를 요구한 사례가 있다 — 채점 문자열 우선
---
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: sqs-scaler
  namespace: ${NAMESPACE}
spec:
  scaleTargetRef:
    name: ${DEPLOYMENT}
  minReplicaCount: 0
  pollingInterval: 15
  cooldownPeriod: 60
  triggers:
    - type: aws-sqs-queue
      authenticationRef:
        name: aws-creds
      metadata:
        queueURL: ${QUEUE_URL}
        awsRegion: ${REGION}
        queueLength: "5"
        scaleOnInFlight: "false"
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

```powershell
$k = Get-Content k8s/30-keda-scaledobject.yaml -Raw
$k = $k.Replace('${QUEUE_URL}',  (terraform output -raw sqs_queue_url)) `
       .Replace('${REGION}',     'ap-northeast-2') `
       .Replace('${NAMESPACE}',  'skills') `
       .Replace('${DEPLOYMENT}', 'sqs-worker')
$k | kubectl apply -f -

kubectl get scaledobject,triggerauthentication -n skills
kubectl get hpa -n skills          # keda-hpa-<scaledobject> 가 생겨야 정상
aws sqs get-queue-attributes `
  --queue-url (terraform output -raw sqs_queue_url) `
  --attribute-names ApproximateNumberOfMessages
```

```hcl
# 파일: set-XX/task-2/module-N/terraform/outputs.tf
output "sqs_queue_url" { value = aws_sqs_queue.this.url }
output "sqs_queue_arn" { value = aws_sqs_queue.this.arn }
```

`podIdentity.provider` 는 KEDA 문서 권장이 `aws`, 채점이 `aws-eks` 를 요구한 사례(set-08 4-4)가 있다. **채점지 문자열이 우선**이지만 KEDA 3.0에서 `aws-eks`·`identityOwner` 가 제거 예정이라 helm이 3.x면 `aws` 만 동작한다:

```powershell
helm search repo kedacore/keda
```

구형 방식(TriggerAuthentication 없이)은 trigger `metadata` 안에 `identityOwner: operator` 다.
</details>

## 3. Karpenter interruption 큐

```hcl
# 파일: set-XX/task-2/module-N/terraform/karpenter-interruption.tf   (KIT에서 복사됨)
resource "aws_sqs_queue" "addon_ekscale_interruption" {
  name                      = var.addon_ekscale_queue_name != "" ? var.addon_ekscale_queue_name : var.addon_ekscale_cluster_name
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true
}
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

```hcl
# 파일: set-XX/task-2/module-N/terraform/outputs.tf
output "karpenter_interruption_queue_name" { value = aws_sqs_queue.addon_ekscale_interruption.name }
output "karpenter_interruption_queue_url"  { value = aws_sqs_queue.addon_ekscale_interruption.url }
```

```powershell
$q = terraform output -raw karpenter_interruption_queue_name
terraform output -raw karpenter_interruption_queue_url

# 컨트롤러 역할 이름 찾기 (eksctl iamserviceaccount 가 만든 것)
aws iam list-roles --query "Roles[?contains(RoleName,'karpenter')].RoleName" --output table

# helm 에 큐 이름 반영 — 재설치가 아니라 upgrade
helm upgrade karpenter oci://public.ecr.aws/karpenter/karpenter -n kube-system --reuse-values `
  --set settings.interruptionQueue=$q

# 실제 반영 확인
kubectl -n kube-system get deploy karpenter -o jsonpath='{.spec.template.spec.containers[0].env}'
aws sqs get-queue-attributes --queue-url (terraform output -raw karpenter_interruption_queue_url) `
  --attribute-names ApproximateNumberOfMessages
```

**큐 이름은 helm `settings.interruptionQueue` 와 정확히 일치해야 한다.** 큐만 만들고 helm에 안 넣으면 아무 일도 안 일어난다.
</details>

## 4. Fargate profile · Addon NG

```powershell
# ${CLUSTER_NAME} ${REGION} 치환 후
eksctl create fargateprofile -f eksctl/fargate-profile.rendered.yaml
eksctl create nodegroup -f eksctl/addon-nodegroup.rendered.yaml
```

```yaml
# 파일: set-XX/task-2/module-N/eksctl/cluster.yaml   (addons 안 — CoreDNS 를 Fargate 에)
- name: coredns
  configurationValues: |
    {"computeType": "Fargate"}
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

```powershell
$c = terraform output -raw cluster_name
aws eks describe-fargate-profile --cluster-name $c --fargate-profile-name "$c-fp-keda" `
  --query fargateProfile.status
aws eks list-fargate-profiles --cluster-name $c
kubectl get nodes -L eks.amazonaws.com/compute-type

# Addon NG 의 taint 확인
kubectl get nodes -o json | ConvertFrom-Json |
  Select-Object -ExpandProperty items |
  Select-Object @{n='node';e={$_.metadata.name}}, @{n='taints';e={$_.spec.taints.key -join ','}}
```

Fargate profile은 생성에 수 분, **삭제도 수 분** 걸린다. 이름은 `${CLUSTER_NAME}-fp-*` 이지만 과제지 명시 이름이 있으면 정확 일치시킨다.

taint 있는 NG에 helm 컴포넌트를 올리려면 values에 `tolerations` 가 필요하다 (KEDA: `operator.tolerations`·`metricsServer.tolerations`·`webhooks.tolerations`. Karpenter는 기본 `CriticalAddonsOnly` toleration이 있다).
</details>

## VERIFY

```powershell
kubectl get nodepool,ec2nodeclass -o wide
kubectl get scaledobject,triggerauthentication -n <ns>
kubectl get hpa -n <ns>
kubectl get nodes -L karpenter.sh/capacity-type,node.kubernetes.io/instance-type
aws eks list-fargate-profiles --cluster-name <클러스터>
```

## TROUBLESHOOT

- NodePool `requirements`·`taints`·`limits`·`disruption` 변경은 in-place(기존 노드는 drift로 순차 교체). EC2NodeClass `amiSelectorTerms`·`blockDeviceMappings` 변경도 in-place지만 **노드 전부 교체**가 일어난다 — 채점 직전엔 건드리지 않는다.
- ScaledObject 수정은 in-place. `scaleTargetRef` 의 Deployment에 `replicas` 를 명시해 두면 KEDA/HPA와 싸운다 — **Deployment에서 replicas를 지운다.**
- spot을 쓰려면 `AWSServiceRoleForEC2Spot` 이 필요하다.
- **interruption 큐 이름은 helm `settings.interruptionQueue` 와 정확 일치.**
- Karpenter 노드 역할은 access entry를 수동 등록해야 한다 — 누락 시 노드 NotReady.
- `podIdentity.provider` 는 KEDA 버전에 따라 다르다. **채점지 문자열 우선**, helm 3.x면 `aws` 만 동작.
- `minReplicaCount: 0` 이면 큐가 비었을 때 Pod 0이다. 채점이 "Pod 최소 N개 유지"를 보면 그 값으로. 0→1은 `pollingInterval` 후에 일어나므로 채점 대기(보통 3분)보다 짧게 잡는다.
- Fargate profile은 생성·삭제 모두 수 분 걸린다.
- eksctl은 `managedNodeGroups` 의 instanceType·taints 변경이 불가하다(새 NG 생성 후 구 NG 삭제). 노드 수(`desiredCapacity`)만 `eksctl scale nodegroup` 으로 in-place다.

## 실전 구현 (참고용)

- set-07 task-2 module-3-eks-scaling `k8s/10-karpenter-nodepool.yaml`(taint·instance-type 채점) · `eksctl/cluster.yaml`(Addon NG taint·access entry) — **가장 가까운 복사 원본**
- set-08 task-2 module-4-sqs-scaling `k8s/30-keda-scaledobject.yaml`(TriggerAuthentication) · `eksctl/cluster.yaml`(Fargate profile 3개·coredns Fargate)
- set-05 task-2 module-1-eks-scaling `k8s/30-karpenter-nodepool.yaml`(limits cpu+memory) · `terraform/iam.tf`(컨트롤러 정책 전문) · `terraform/sqs.tf`
- interruption 큐는 실전 구현이 없다 — 공식 `karpenter cloudformation.yaml` 기준

---

절차 원본은 [KIT-INDEX 30분 루틴](../../../KIT-INDEX.md#30분-루틴), KIT을 두 개 이상 얹을 때는 [여러 KIT을 한꺼번에 얹을 때](../../../KIT-INDEX.md#여러-kit을-한꺼번에-얹을-때), 치환 자리 표기는 [코드 블록에서 바꿔야 하는 자리](../../../KIT-INDEX.md#코드-블록에서-바꿔야-하는-자리)를 본다. 여기 TROUBLESHOOT에 없는 실패는 [공통 트러블슈팅](../../TROUBLESHOOTING-COMMON.md).
