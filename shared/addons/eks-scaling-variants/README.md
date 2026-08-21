# eks-scaling-variants 부착 스니펫

2과제 EKS Scaling 모듈(Karpenter + KEDA + Fargate/Addon NG)에 당일 추가되는 하위 문항용 변형 모음.
set-05 m1 · set-07 m3 · set-08 m4 에 대응한다. 1과제에는 스케일링 문항이 없다(출제지침).

## 파일

- `k8s/10-karpenter-nodepool.yaml` — EC2NodeClass + NodePool 전체 옵션(taint·label·spot·instance-type·expireAfter·limits cpu/memory·disruption·budgets·blockDeviceMappings·metadataOptions)
- `k8s/30-keda-scaledobject.yaml` — TriggerAuthentication(`podIdentity.provider: aws`) + ScaledObject 풀옵션(`minReplicaCount 0`·`pollingInterval`·`cooldownPeriod`·`queueLength`·`scaleOnInFlight`·HPA behavior)
- `eksctl/fargate-profile.yaml` — Fargate profile 3개(keda·karpenter·kube-system). 기존 클러스터에 `eksctl create fargateprofile -f`
- `eksctl/addon-nodegroup.yaml` — taint(`CriticalAddonsOnly`) 붙은 Addon 관리형 노드그룹. 기존 클러스터에 `eksctl create nodegroup -f`
- `terraform/karpenter-interruption.tf`·`variables.tf` — interruption SQS 큐 + EventBridge 룰 4종 + 컨트롤러 정책(`addon_ekscale_*`)

## 부착 절차

1. k8s: 플레이스홀더를 치환해 apply 한다. 기존 NodePool/ScaledObject 를 고치는 문항이면 새 파일 대신 기존 파일에 해당 블록만 옮긴다.

   ```powershell
   $c = Get-Content k8s/10-karpenter-nodepool.yaml -Raw
   $c = $c.Replace('${CLUSTER_NAME}', 'skills-eks').Replace('${NODE_ROLE_NAME}', (terraform -chdir=terraform output -raw karpenter_node_role_name))
   $c | kubectl apply -f -
   $k = Get-Content k8s/30-keda-scaledobject.yaml -Raw
   $k = $k.Replace('${QUEUE_URL}', (terraform -chdir=terraform output -raw sqs_queue_url)).Replace('${REGION}', 'ap-northeast-2').Replace('${NAMESPACE}', 'skills').Replace('${DEPLOYMENT}', 'sqs-worker')
   $k | kubectl apply -f -
   ```

2. eksctl: `${CLUSTER_NAME}` `${REGION}` 치환 후 한 줄.

   ```powershell
   eksctl create fargateprofile -f eksctl/fargate-profile.rendered.yaml
   eksctl create nodegroup -f eksctl/addon-nodegroup.rendered.yaml
   ```

3. terraform(interruption): `terraform/*.tf` 를 `set-XX/task-2/module-N/terraform/` 으로 복사.

   ```hcl
   addon_ekscale_cluster_name        = "skills-eks"
   addon_ekscale_queue_name          = ""    # 비우면 클러스터 이름
   addon_ekscale_karpenter_role_name = "eksctl-skills-eks-addon-iamserviceaccount-kube-system-karpenter-Role1-xxxx"
   ```

   Karpenter 컨트롤러 역할 이름은 `aws iam list-roles --query "Roles[?contains(RoleName,'karpenter')].RoleName"`. 기존 컨트롤러 정책 리소스를 직접 참조하려면 attach 리소스 대신 `aws_iam_policy.karpenter` 의 Statement 에 `AllowInterruptionQueueActions` 문장을 합친다.
   `terraform fmt` → `validate` → `plan` 으로 기존 리소스 diff 없음 확인 → `apply`.
4. helm 에 큐 이름 반영(재설치 아님, upgrade):

   ```powershell
   helm upgrade karpenter oci://public.ecr.aws/karpenter/karpenter -n kube-system --reuse-values --set settings.interruptionQueue=skills-eks
   ```

5. 검증:

   ```powershell
   kubectl get nodepool,ec2nodeclass -o wide
   kubectl get scaledobject,triggerauthentication -n skills
   kubectl get hpa -n skills          # keda-hpa-<scaledobject> 가 생겨야 정상
   aws eks describe-fargate-profile --cluster-name skills-eks --fargate-profile-name skills-eks-fp-keda --query fargateProfile.status
   aws sqs get-queue-attributes --queue-url (aws sqs get-queue-url --queue-name skills-eks --query QueueUrl --output text) --attribute-names ApproximateNumberOfMessages
   ```

## 블록

spot 요구 — NodePool `requirements` 안에:

```yaml
- key: karpenter.sh/capacity-type
  operator: In
  values: ["spot", "on-demand"]   # spot 우선, 미가용 시 on-demand
```

KEDA 2.x 구형 방식(TriggerAuthentication 없이) — ScaledObject trigger `metadata` 안에:

```yaml
identityOwner: operator   # KEDA 3.0 제거 예정. set-05/07 방식. 채점이 TriggerAuthentication 을 보면 안 됨
```

CoreDNS 를 Fargate 에 올릴 때 — cluster.yaml `addons` 안에:

```yaml
- name: coredns
  configurationValues: |
    {"computeType": "Fargate"}
```

## 함정

- NodePool `requirements`·`taints`·`limits`·`disruption` 변경은 in-place(기존 노드는 drift 로 순차 교체). EC2NodeClass `amiSelectorTerms`·`blockDeviceMappings` 변경도 in-place 지만 **노드 전부 교체**가 일어난다 — 채점 직전엔 건드리지 않는다.
- ScaledObject 수정은 in-place. `scaleTargetRef` 의 Deployment 에 `replicas` 를 명시해 두면 KEDA/HPA 와 싸운다 — Deployment 에서 replicas 를 지운다.
- spot 을 쓰려면 계정에 `AWSServiceRoleForEC2Spot` 가 있어야 한다: `aws iam create-service-linked-role --aws-service-name spot.amazonaws.com` (이미 있으면 에러 무시). 컨트롤러 정책의 `spot-instances-request/*` 리소스·`ec2:DescribeSpotPriceHistory` 는 set-05/07/08 정책에 이미 있다.
- interruption 큐 이름은 helm `settings.interruptionQueue` 와 **정확 일치**. 큐만 만들고 helm 에 안 넣으면 아무 일도 안 일어난다.
- Karpenter 가 띄운 노드의 역할은 eksctl 이 access entry 를 자동으로 만들지 않는다 — `accessConfig.accessEntries` 에 `EC2_LINUX` 로 등록(set-07/08 cluster.yaml). 누락 시 노드 NotReady.
- `podIdentity.provider`: KEDA 문서 권장은 `aws`, 채점 스크립트가 `aws-eks` 를 요구한 사례(set-08 4-4, 2026-08-07 정정)가 있다. **채점지 문자열 우선**. KEDA 3.0 에서 `aws-eks`·`identityOwner` 제거 예정이라 helm 최신이 3.x 면 `aws` 만 동작한다 — `helm search repo kedacore/keda` 로 버전 확인.
- `minReplicaCount: 0` 이면 큐가 비었을 때 Pod 0 → 채점이 "Pod 최소 N개 유지" 를 보면 그 값으로. 0→1 은 `pollingInterval` 후에 일어나므로 채점 대기 시간(보통 3분)보다 짧게.
- Fargate profile 은 생성에 수 분, **삭제도 수 분**. 이름은 `${CLUSTER_NAME}-fp-*` 로 두었으나 과제지 명시 이름이 있으면 정확 일치.
- taint 있는 NG 에 helm 컴포넌트를 올리려면 values 에 `tolerations` 필요(KEDA: `operator.tolerations`·`metricsServer.tolerations`·`webhooks.tolerations`, Karpenter: 기본 `CriticalAddonsOnly` toleration 있음).
- eksctl 은 `managedNodeGroups` 의 instanceType·taints 변경이 불가(⚠ 새 NG 생성 후 구 NG 삭제). 노드 수(`desiredCapacity`)만 `eksctl scale nodegroup` 으로 in-place.

## 실전 구현 (참고용)

- set-07 task-2 module-3-eks-scaling `k8s/10-karpenter-nodepool.yaml`(taint·instance-type 채점) · `eksctl/cluster.yaml`(Addon NG taint·access entry)
- set-08 task-2 module-4-sqs-scaling `k8s/30-keda-scaledobject.yaml`(TriggerAuthentication) · `eksctl/cluster.yaml`(Fargate profile 3개·coredns Fargate)
- set-05 task-2 module-1-eks-scaling `k8s/30-karpenter-nodepool.yaml`(limits cpu+memory) · `terraform/iam.tf`(컨트롤러 정책 전문) · `terraform/sqs.tf`
- interruption 큐 실전 구현 없음 — 공식 `karpenter/website/content/en/docs/reference/cloudformation.yaml` 기준
