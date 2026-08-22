# EKS 로깅·암호화·노드 강화 부착 KIT

클러스터 자체의 설정 묶음 — Control Plane 로깅 · Secret envelope CMK · 노드 EBS CMK · 노드 KST · IMDS 차단 · 로그 그룹 CMK · EBS CSI 암호화 StorageClass.

## 이 KIT이 맞나

- 과제지에 **"Control Plane 로그"·"Secret 암호화"·"IMDSv1 차단"·"노드 볼륨 암호화"·"노드 시간대"** → 맞다.
- **노드 자동 확장** → [eks-scaling-variants](../eks-scaling-variants/README.md).
- **Pod 로그 수집** → [observability](../observability/README.md) 경로 C.
- **CMK 자체 생성** → [kms](../kms/README.md).

## 세트별 현재 강화 상태

| | set-02 | set-03 | set-07 |
| --- | --- | --- | --- |
| 클러스터 | `wskorea26-cluster` | `wsc2026-eks-cluster` | `unicorn-eks-cluster` |
| `cloudWatch.clusterLogging` | **있음** (5종) | **있음** (5종) | **있음** (5종) |
| `secretsEncryption.keyARN` | `${EKS_KMS_ARN}` | `${EKS_KMS_ARN}` | `${PLATFORM_KMS_ARN}` |
| `volumeEncrypted` | 있음 (기본 키) | 있음 (기본 키) | 있음 |
| `volumeKmsKeyID` | **없음** (AWS 관리 키) | **없음** | `${PLATFORM_KMS_ARN}` |
| `disableIMDSv1` | 있음 | 있음 | 있음 |
| `disablePodIMDS` | **없음** | **없음** | **없음** |
| `preBootstrapCommands` (KST) | **없음** | **없음** | **있음** (앵커 `&common_bootstrap`) |
| Control Plane 로그 그룹 선생성 | **없음** | **없음** | **있음** (`aws_cloudwatch_log_group.eks_cluster`) |
| StorageClass | **없음** | **없음** | `k8s/01-storageclass.yaml` |

**세 세트 모두 로깅·Secret 암호화·IMDSv1 차단은 이미 되어 있다.** 새 문항이면 대개 남은 칸(노드 EBS CMK, KST, 로그 그룹 CMK, StorageClass)이다.

## 복사할 파일

| 원본 | 대상 | 내용 |
| --- | --- | --- |
| `terraform/kms-eks.tf` · `variables.tf` | `set-XX/task-1/terraform/` | 플랫폼 CMK(key policy: root·logs·AutoScaling) + alias + 로그 그룹 선생성 + EBS CSI KMS 정책 |
| `eksctl/nodegroup-hardened.yaml` | `set-XX/task-1/eksctl/` | EBS CMK·KST·IMDS 강화 관리형 NG (기존 클러스터에 `eksctl create nodegroup -f`) |
| `attach-existing-cluster.sh` | 실행용 | 기존 클러스터에 로깅·Secret envelope·로그 그룹 CMK 부착 (재생성 없음) |
| `k8s/storageclass.yaml` | `set-XX/task-1/k8s/` | EBS CSI StorageClass (`encrypted`·`kmsKeyId`·`WaitForFirstConsumer`) |

기존 `aws_kms_key` 가 있으면 KIT의 키 리소스는 지우고 `aws_kms_key.addon_ekslog.arn` 을 기존 키로 치환한다 — 단 **기존 key policy에 `AllowCloudWatchLogs`·`AllowAutoScalingUse/Grant` 문장을 합쳐야 한다.**

## CHANGE — 당일 고치는 값

| 변수 | 기본값 | 무엇 |
| --- | --- | --- |
| `addon_ekslog_cluster_name` | **필수** | 클러스터 이름. 로그 그룹 `/aws/eks/<이름>/cluster` 와 EBS CSI 정책 이름에 쓴다 |
| `addon_ekslog_kms_alias` | `"eks-platform-key"` | CMK alias. 과제지 명시 이름과 정확히 일치 |
| `addon_ekslog_kms_rotation_days` | `365` | 회전 주기(일) |
| `addon_ekslog_log_retention_days` | `30` | Control Plane 로그 보존 |
| `addon_ekslog_create_cluster_log_group` | `true` | 클러스터가 **이미 있으면 false** 로 두고 `associate-kms-key` 로 간다 |

## CHECK · RUN

```powershell
aws sts get-caller-identity; aws configure get region
terraform fmt; terraform init; terraform validate
terraform plan; terraform apply       # terraform 이 먼저다 (로그 그룹·키가 있어야 한다)
```

## 0. 키·정책 output

```hcl
# 파일: set-XX/task-1/terraform/outputs.tf
output "addon_ekslog_kms_arn"             { value = aws_kms_key.addon_ekslog.arn }
output "addon_ekslog_ebs_csi_policy_arn"  { value = aws_iam_policy.addon_ekslog_ebs_csi.arn }
output "eks_cluster_log_group"            { value = aws_cloudwatch_log_group.addon_ekslog_cluster[0].name }
```

<details><summary><b>값 뽑기 — 세트별 (기존 키를 재사용할 때)</b></summary>

| 세트 | 기존 EKS 키 | output |
| --- | --- | --- |
| set-02 | `aws_kms_key.eks` | `eks_kms_arn` (있음) |
| set-03 | `aws_kms_key.eks` | `eks_kms_arn` (있음) |
| set-07 | `aws_kms_key.platform` (+ us-east-1 replica) | `platform_kms_arn` (있음) |

```powershell
terraform output -raw eks_kms_arn         # set-02 / set-03
terraform output -raw platform_kms_arn    # set-07
terraform output -raw addon_ekslog_kms_arn   # 새로 만든 경우

# key policy 에 logs·AutoScaling 문장이 있는지 (없으면 아래 블록들이 조용히 실패한다)
aws kms get-key-policy --key-id (terraform output -raw eks_kms_arn) --policy-name default `
  --query Policy --output text | ConvertFrom-Json |
  Select-Object -ExpandProperty Statement | Select-Object Sid, Principal
```
</details>

## 1. Control Plane 로깅

```yaml
# 파일: set-XX/task-1/eksctl/cluster.yaml   (ClusterConfig 최상위)
cloudWatch:
  clusterLogging:
    enableTypes: ["api", "audit", "authenticator", "controllerManager", "scheduler"]   # = all
    # logRetentionInDays: 30   # eksctl 이 로그 그룹을 만들 때만 적용 — terraform 선생성이면 무시된다
```

기존 클러스터엔:

```powershell
eksctl utils update-cluster-logging --cluster <클러스터> --region ap-northeast-2 --enable-types all --approve
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

**세 세트 모두 이미 5종이 켜져 있다.** 확인만 한다:

```powershell
# set-02
aws eks describe-cluster --name wskorea26-cluster --region ap-northeast-2 `
  --query "cluster.logging.clusterLogging[?enabled].types[]"
# set-03
aws eks describe-cluster --name wsc2026-eks-cluster --region ap-northeast-2 `
  --query "cluster.logging.clusterLogging[?enabled].types[]"
# set-07
aws eks describe-cluster --name unicorn-eks-cluster --region ap-northeast-2 `
  --query "cluster.logging.clusterLogging[?enabled].types[]"

aws logs describe-log-groups --log-group-name-prefix /aws/eks/ `
  --query "logGroups[].[logGroupName,retentionInDays,kmsKeyId]" --output table
```

`eksctl utils update-cluster-logging` 은 `--approve` 없으면 plan만 찍고 끝난다.
</details>

## 2. Secret envelope 암호화

```yaml
# 파일: set-XX/task-1/eksctl/cluster.yaml   (ClusterConfig 최상위)
secretsEncryption:
  keyARN: "${KMS_ARN}"      # alias 가 아니라 key ARN
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

| 세트 | env 변수 | 소스 output |
| --- | --- | --- |
| set-02 | `EKS_KMS_ARN` | `eks_kms_arn` |
| set-03 | `EKS_KMS_ARN` | `eks_kms_arn` |
| set-07 | `PLATFORM_KMS_ARN` | `platform_kms_arn` |

```powershell
$env:EKS_KMS_ARN = terraform output -raw eks_kms_arn          # set-02 / set-03
$env:PLATFORM_KMS_ARN = terraform output -raw platform_kms_arn # set-07

aws eks describe-cluster --name <클러스터> --region ap-northeast-2 `
  --query "cluster.encryptionConfig[0].provider.keyArn"

# 이미 만든 클러스터에 부착 (재생성 없음)
eksctl utils enable-secrets-encryption --cluster <클러스터> --region ap-northeast-2 --key-arn $env:EKS_KMS_ARN
```

**Secret envelope은 켜면 못 끈다** (키 교체도 불가). 키 ARN을 틀리면 클러스터 재생성뿐이다.
</details>

## 3. 노드 EBS CMK · IMDS · KST

```yaml
# 파일: set-XX/task-1/eksctl/cluster.yaml   (managedNodeGroups 항목 안)
volumeEncrypted: true
volumeKmsKeyID: "${KMS_ARN}"
disableIMDSv1: true      # httpTokens=required
disablePodIMDS: true     # httpPutResponseHopLimit=1
preBootstrapCommands:
  - "ln -sf /usr/share/zoneinfo/Asia/Seoul /etc/localtime || true"
  - "timedatectl set-timezone Asia/Seoul || true"
```

<details><summary><b>값 뽑기 — 세트별 (전부 NG 재생성이다)</b></summary>

| 세트 | 지금 있는 것 | 새로 넣을 것 |
| --- | --- | --- |
| set-02 | `volumeEncrypted`·`disableIMDSv1` | `volumeKmsKeyID` · `disablePodIMDS` · KST |
| set-03 | `volumeEncrypted`·`disableIMDSv1` | `volumeKmsKeyID` · `disablePodIMDS` · KST |
| set-07 | 전부 있음 (`preBootstrapCommands` 는 YAML 앵커 `&common_bootstrap`) | `disablePodIMDS` 만 |

```powershell
$env:KMS_ARN = terraform output -raw platform_kms_arn    # 세트별 output

# 현재 노드 상태 확인
aws ec2 describe-instances --filters "Name=tag:eks:cluster-name,Values=<클러스터>" `
  --query "Reservations[].Instances[].{id:InstanceId,imds:MetadataOptions.HttpTokens,hop:MetadataOptions.HttpPutResponseHopLimit}" --output table
aws ec2 describe-volumes --filters "Name=tag:eks:cluster-name,Values=<클러스터>" `
  --query "Volumes[].[VolumeId,Encrypted,KmsKeyId]" --output table
kubectl debug node/<노드> -it --image=busybox -- date    # 노드 TZ
```

**MNG는 launch template이 고정이라 `eksctl update nodegroup` 으로 못 바꾼다.** 새 NG를 만들고 구 NG를 뺀다:

```powershell
eksctl create nodegroup -f eksctl/nodegroup-hardened.rendered.yaml
kubectl get nodes -L eks.amazonaws.com/nodegroup          # 새 NG Ready 확인
eksctl delete nodegroup --cluster <클러스터> --region ap-northeast-2 --name <구 NG> --drain=true
```

구 NG를 지우면 그 위 Pod가 전부 옮겨간다. **nodeSelector가 구 NG label을 가리키면 새 NG label을 같게 둔다** — set-02는 `wskorea26/node`, set-03은 `wsc2026/node`, set-07은 `unicorn` label을 쓴다.

`key policy` 에 `AllowAutoScalingUse`/`AllowAutoScalingGrant` 가 없으면 인스턴스가 **조용히 terminate** 된다:

```powershell
aws autoscaling describe-scaling-activities --auto-scaling-group-name <ASG명> --max-items 5 `
  --query "Activities[].[StatusCode,StatusMessage]"
# → Client.InternalError: Client error on launch
```
</details>

## 4. 로그 그룹 CMK

```hcl
# 파일: set-XX/task-1/terraform/cloudwatch.tf
# 기존 aws_cloudwatch_log_group 리소스 블록 *안에* (in-place)
kms_key_id = aws_kms_key.addon_ekslog.arn
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

| 세트 | Control Plane 로그 그룹 선생성 | 다른 로그 그룹 |
| --- | --- | --- |
| set-02 | **없음** — EKS가 만든다(CMK 없이) | `pod_logs` · `book_lambda` |
| set-03 | **없음** | `book_app` · `book_function` |
| set-07 | **있음** `aws_cloudwatch_log_group.eks_cluster` | `book_app` · `get_booking` · `flowlog` · `waf`(us-east-1) |

```powershell
aws logs describe-log-groups --log-group-name-prefix /aws/eks/<클러스터>/ `
  --query "logGroups[].[logGroupName,kmsKeyId]"

# 이미 생긴 로그 그룹에 나중에 키를 붙이기
aws logs associate-kms-key --log-group-name /aws/eks/<클러스터>/cluster `
  --kms-key-id (terraform output -raw eks_kms_arn)
```

EKS가 먼저 만들면 CMK 없이 생긴다. Terraform 선생성과 둘 다 하면 apply가 "already exists"로 실패하니:

```powershell
terraform import aws_cloudwatch_log_group.addon_ekslog_cluster[0] /aws/eks/<클러스터>/cluster
```

key policy에 `AllowCloudWatchLogs` 가 **먼저** 있어야 한다 — 순서가 반대면 `AccessDeniedException`.
</details>

## 5. EBS CSI 암호화 StorageClass

```yaml
# 파일: set-XX/task-1/k8s/01-storageclass.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: addon-gp3-encrypted
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
parameters:
  type: gp3
  encrypted: "true"
  kmsKeyId: "${KMS_ARN}"
```

<details><summary><b>값 뽑기 — 세트별</b></summary>

| 세트 | 기존 StorageClass | EBS CSI 역할 |
| --- | --- | --- |
| set-02 | **없음** | 없음 (Pod Identity/IRSA 미구성) |
| set-03 | **없음** | 없음 |
| set-07 | `k8s/01-storageclass.yaml` **있음** | `aws_iam_role.ebs_csi` + `aws_iam_role_policy.ebs_csi_kms` |

```powershell
$env:KMS_ARN = terraform output -raw platform_kms_arn
(Get-Content k8s/01-storageclass.yaml -Raw).Replace('${KMS_ARN}', $env:KMS_ARN) | kubectl apply -f -
kubectl get sc

# CSI 역할에 KMS 정책 붙이기 (set-02 / set-03)
aws iam attach-role-policy --role-name <ebs-csi 역할> `
  --policy-arn (terraform output -raw addon_ekslog_ebs_csi_policy_arn)

# PVC 가 Pending 이면 여기에 이유가 나온다
kubectl describe pvc <이름>
# → AccessDeniedException ... kms:GenerateDataKeyWithoutPlaintext = 정책 누락
```

eksctl addon 경로면 `cluster.yaml` 의 `addons[aws-ebs-csi-driver].attachPolicyARNs` 에 ARN을 넣는다.

StorageClass `parameters` 는 **생성 후 불변**(재생성)이다. 기존 PVC는 영향 없다.
</details>

## VERIFY

```powershell
$c = "<클러스터>"
aws eks describe-cluster --name $c --region ap-northeast-2 `
  --query "{logging:cluster.logging.clusterLogging[0].types,kms:cluster.encryptionConfig[0].provider.keyArn}"
aws logs describe-log-groups --log-group-name-prefix "/aws/eks/$c/" --query "logGroups[].[logGroupName,kmsKeyId]"
aws ec2 describe-instances --filters "Name=tag:eks:cluster-name,Values=$c" `
  --query "Reservations[].Instances[].{id:InstanceId,imds:MetadataOptions.HttpTokens,hop:MetadataOptions.HttpPutResponseHopLimit}"
aws ec2 describe-volumes --filters "Name=tag:eks:cluster-name,Values=$c" --query "Volumes[].[VolumeId,Encrypted,KmsKeyId]"
kubectl get sc
```

## TROUBLESHOOT

- **Secret envelope은 켜면 못 끈다.** 키 ARN이 같은 리전·같은 계정인지, alias가 아니라 **key ARN** 인지 확인한다.
- 노드 EBS CMK·IMDS·`preBootstrapCommands` 는 **NG 재생성**이다. MNG는 launch template이 고정이다.
- `volumeKmsKeyID` 를 줬는데 key policy에 AutoScaling 문장이 없으면 인스턴스가 **조용히 terminate** 되고 eksctl이 타임아웃난다.
- 로그 그룹 `kms_key_id` 는 in-place지만 key policy에 `AllowCloudWatchLogs` 가 먼저 있어야 한다.
- Control Plane 로그 그룹은 EKS가 먼저 만들면 CMK 없이 생긴다 — 선생성 또는 `associate-kms-key`.
- IMDS hop limit 숫자 직접 지정은 eksctl 필드가 없다 — `disablePodIMDS: true`(hop 1)만 지원한다.
- `preBootstrapCommands` 는 AL2023에서 eksctl 0.198.0+ 필요하다. `eksctl version` 을 먼저 본다.
- **노드 TZ와 컨테이너 TZ는 별개다.** 앱 로그 시각까지 KST를 보려면 Pod에 `/usr/share/zoneinfo/Asia/Seoul` hostPath 마운트(set-07 `deployment.yaml`)나 `TZ` env가 필요하다.
- StorageClass `parameters` 는 생성 후 불변이다.

## 실전 구현 (참고용)

- set-07 task-1 `eksctl/cluster.yaml`(cloudWatch·secretsEncryption·volumeKmsKeyID·disableIMDSv1·preBootstrapCommands KST) · `terraform/kms.tf`(logs MRK·AutoScaling 정책) · `terraform/cloudwatch.tf`(로그 그룹 선생성) · `k8s/01-storageclass.yaml`
- set-02 / set-03 task-1 `eksctl/cluster.yaml` — 로깅 5종 + secretsEncryption + `volumeEncrypted`·`disableIMDSv1`
- set-05 task-1 `eksctl/cluster.yaml`(disablePodIMDS·addon attachPolicyARNs) · `terraform/iam.tf`(ebs_csi_kms)
- set-07 task-2 module-4-container-logging `eksctl/cluster.yaml`(preBootstrapCommands timedatectl)
