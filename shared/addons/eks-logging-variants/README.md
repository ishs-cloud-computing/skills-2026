# eks-logging-variants 부착 스니펫

**STATUS:** `VALIDATED` — `terraform validate` 통과 (2026-08-22). AWS 에 apply 한 검증은 아니다.

## USE WHEN

EKS 클러스터 자체의 로깅·암호화·노드 강화 문항 묶음 — Control Plane 로깅, Secret envelope CMK,
노드 EBS CMK, 노드 KST, IMDS 차단, 로그 그룹 CMK, EBS CSI 암호화 StorageClass.
1과제 KMS/Security 옵션(set-02/03/05 task-1 후보)과 set-08 m4 에 대응한다.

## CHANGE — 당일 고치는 값

`terraform.tfvars` 에 넣는다. **필수 1개**는 채우지 않으면 apply 되지 않는다.

| 변수 | 기본값 | 무엇 |
| --- | --- | --- |
| `addon_ekslog_cluster_name` | **필수** | EKS 클러스터 이름. Control Plane 로그 그룹 /aws/eks/<이름>/cluster 와 EBS CSI 정책 이름에 쓴다 |
| `addon_ekslog_kms_alias` | `"eks-platform-key"` | EKS 플랫폼 CMK alias (alias/ 접두어 제외). 과제지 명시 이름과 정확히 일치시킨다 |
| `addon_ekslog_kms_rotation_days` | `365` | CMK 자동 회전 주기 (일). 과제지가 지정하면 그 값으로 |
| `addon_ekslog_log_retention_days` | `30` | Control Plane 로그 그룹 보존 일수 |
| `addon_ekslog_create_cluster_log_group` | `true` | true 면 /aws/eks/<cluster>/cluster 로그 그룹을 CMK 로 선생성한다 (eksctl 보다 먼저 apply). 클러스터가 이미 있으면 false 로 두고 README 의 associate-kms-key 로 간다 |

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

- `terraform/kms-eks.tf`·`variables.tf` — 플랫폼 CMK(key policy: root·logs·AutoScaling) + alias + Control Plane 로그 그룹 선생성(CMK) + EBS CSI KMS 정책(`addon_ekslog_*`)
- `eksctl/nodegroup-hardened.yaml` — EBS CMK·KST·IMDS 강화 관리형 NG. 기존 클러스터에 `eksctl create nodegroup -f`
- `attach-existing-cluster.sh` — 기존 클러스터에 Control Plane 로깅·Secret envelope·로그 그룹 CMK 부착(재생성 없음)
- `k8s/storageclass.yaml` — EBS CSI StorageClass(`encrypted`·`kmsKeyId`·`WaitForFirstConsumer`)

## 부착 절차

1. `terraform/*.tf` 를 `set-XX/task-1/terraform/` 으로 복사. 기존 `aws_kms_key` 가 있으면 이 파일의 키 리소스는 지우고 `aws_kms_key.addon_ekslog.arn` 을 기존 키로 치환 — 단 기존 key policy 에 `AllowCloudWatchLogs`·`AllowAutoScalingUse/Grant` 문장을 합쳐야 한다.

   ```hcl
   addon_ekslog_cluster_name             = "skills-eks"
   addon_ekslog_kms_alias                = "skills-eks-key"     # 과제지 명시 이름
   addon_ekslog_kms_rotation_days        = 365
   addon_ekslog_log_retention_days       = 30
   addon_ekslog_create_cluster_log_group = true                 # 클러스터가 이미 있으면 false
   ```

   `terraform fmt` → `validate` → `plan` 으로 기존 리소스 diff 없음 확인 → `apply`.
2. **새 클러스터**(cluster.yaml 에 블록 추가 → `eksctl create cluster -f`): 아래 "블록" 절의 `cloudWatch`·`secretsEncryption`·노드그룹 항목을 cluster.yaml 에 넣는다. terraform apply 가 먼저다(로그 그룹·키가 있어야 한다).
3. **기존 클러스터**(재생성 금지):

   ```bash
   CLUSTER=skills-eks REGION=ap-northeast-2 KMS_ARN=$(terraform output -raw addon_ekslog_kms_arn) bash attach-existing-cluster.sh
   ```

   노드 EBS CMK·KST·IMDS 는 기존 NG 를 못 고친다 — 새 NG 를 만들고 구 NG 를 뺀다:

   ```powershell
   # ${CLUSTER_NAME} ${REGION} ${KMS_ARN} 치환 후
   eksctl create nodegroup -f eksctl/nodegroup-hardened.rendered.yaml
   kubectl get nodes -L eks.amazonaws.com/nodegroup          # 새 NG Ready 확인
   eksctl delete nodegroup --cluster skills-eks --region ap-northeast-2 --name <구 NG> --drain=true
   ```

   ⚠ 구 NG 를 지우면 그 위 Pod 가 전부 옮겨간다. nodeSelector 가 구 NG label 을 가리키면 새 NG label 을 같게 둔다.
4. StorageClass: EBS CSI 컨트롤러 SA 역할에 `addon_ekslog_ebs_csi_kms_policy_arn` 을 붙인 뒤

   ```powershell
   aws iam attach-role-policy --role-name <ebs-csi 역할> --policy-arn (terraform output -raw addon_ekslog_ebs_csi_kms_policy_arn)
   (Get-Content k8s/storageclass.yaml -Raw).Replace('${KMS_ARN}', (terraform output -raw addon_ekslog_kms_arn)) | kubectl apply -f -
   ```

   eksctl addon 경로면 cluster.yaml `addons[aws-ebs-csi-driver].attachPolicyARNs` 에 ARN 을 넣는다(set-05 task-1).
5. 검증:

   ```powershell
   aws eks describe-cluster --name skills-eks --query '{logging:cluster.logging.clusterLogging[0].types,kms:cluster.encryptionConfig[0].provider.keyArn}'
   aws logs describe-log-groups --log-group-name-prefix /aws/eks/skills-eks/ --query 'logGroups[].[logGroupName,kmsKeyId]'
   aws ec2 describe-instances --filters Name=tag:eks:cluster-name,Values=skills-eks --query 'Reservations[].Instances[].{id:InstanceId,imds:MetadataOptions.HttpTokens,hop:MetadataOptions.HttpPutResponseHopLimit}'
   aws ec2 describe-volumes --filters Name=tag:eks:cluster-name,Values=skills-eks --query 'Volumes[].[VolumeId,Encrypted,KmsKeyId]'
   kubectl get sc addon-gp3-encrypted -o yaml
   # 노드 TZ
   kubectl debug node/<노드> -it --image=busybox -- date   # 또는 SSM: timedatectl
   ```

## 블록

Control Plane 로깅 — cluster.yaml 최상위:

```yaml
cloudWatch:
  clusterLogging:
    enableTypes: ["api", "audit", "authenticator", "controllerManager", "scheduler"]   # = all
    # logRetentionInDays: 30   # eksctl 이 로그 그룹을 만들 때만 적용 — terraform 선생성이면 무시
```

Secret envelope — cluster.yaml 최상위:

```yaml
secretsEncryption:
  keyARN: "${KMS_ARN}"
```

노드 EBS CMK·IMDS·KST — `managedNodeGroups` 항목 안에:

```yaml
volumeEncrypted: true
volumeKmsKeyID: "${KMS_ARN}"
disableIMDSv1: true      # httpTokens=required
disablePodIMDS: true     # httpPutResponseHopLimit=1
preBootstrapCommands:
  - "ln -sf /usr/share/zoneinfo/Asia/Seoul /etc/localtime || true"
  - "timedatectl set-timezone Asia/Seoul || true"
```

로그 그룹 CMK — 기존 `aws_cloudwatch_log_group` 리소스 안에(in-place):

```hcl
# aws_cloudwatch_log_group 리소스 안에:
kms_key_id = aws_kms_key.addon_ekslog.arn
```

## TROUBLESHOOT — 이 KIT 고유 함정
- **Secret envelope 은 켜면 못 끈다**(키 교체도 불가). 키 ARN 을 틀리면 클러스터 재생성뿐. 키가 같은 리전·같은 계정인지, alias 가 아니라 **key ARN** 인지 확인.
- 노드 EBS CMK·IMDS·preBootstrapCommands 는 ⚠ NG 재생성. MNG 는 launch template 이 고정이라 `eksctl update nodegroup` 으로 못 바꾼다.
- `volumeKmsKeyID` 를 줬는데 key policy 에 `AllowAutoScalingUse`/`AllowAutoScalingGrant` 가 없으면 인스턴스가 **조용히 terminate** 되고 eksctl 이 타임아웃난다. ASG 활동 기록(`Client.InternalError: Client error on launch`)으로 확인.
- 로그 그룹 `kms_key_id` 는 in-place 지만 key policy 에 `AllowCloudWatchLogs` 가 먼저 있어야 한다. 순서가 반대면 AccessDeniedException.
- Control Plane 로그 그룹은 eksctl/EKS 가 먼저 만들면 CMK 없이 생긴다 — terraform 선생성(`addon_ekslog_create_cluster_log_group=true`) 또는 생성 후 `aws logs associate-kms-key`. 둘 다 하면 terraform 이 "already exists" 로 실패하니 `terraform import aws_cloudwatch_log_group.addon_ekslog_cluster[0] /aws/eks/<cluster>/cluster`.
- `eksctl utils update-cluster-logging` 은 `--approve` 없으면 plan 만 찍고 끝난다.
- IMDS hop limit 숫자 직접 지정(2 등)은 eksctl 필드가 없다 — `disablePodIMDS: true` = hop 1 만 지원. 다른 값은 launch template 을 직접 만들어야 하므로 "확인 필요".
- `preBootstrapCommands` 는 AL2023 에서 eksctl 0.198.0+ 필요(issue #7903). 구버전이면 nodeadm config 로 가야 하므로 `eksctl version` 먼저.
- 노드 TZ 와 **컨테이너 TZ 는 별개**. 앱 로그 시각까지 KST 를 보면 Pod 에 `/usr/share/zoneinfo/Asia/Seoul` hostPath 마운트(set-07 task-1 deployment.yaml)나 `TZ` env 가 필요하다.
- StorageClass `parameters` 는 생성 후 불변(⚠ 재생성). 기존 PVC 는 영향 없다.
- EBS CSI 가 CMK PV 를 만들 때 SA 역할에 KMS 정책이 없으면 PVC 가 Pending, 이벤트에 `AccessDeniedException ... kms:GenerateDataKeyWithoutPlaintext`.

## 실전 구현 (참고용)

- set-07 task-1 `eksctl/cluster.yaml`(cloudWatch·secretsEncryption·volumeKmsKeyID·disableIMDSv1·preBootstrapCommands KST) · `terraform/kms.tf`(kms_platform 정책: logs MRK·AutoScaling) · `terraform/cloudwatch.tf`(로그 그룹 선생성) · `k8s/01-storageclass.yaml`
- set-05 task-1 `eksctl/cluster.yaml`(disablePodIMDS·addon attachPolicyARNs) · `terraform/iam.tf`(ebs_csi_kms) · `k8s/02-storageclass.yaml`(Retain)
- set-07 task-2 module-4-container-logging `eksctl/cluster.yaml`(preBootstrapCommands timedatectl)
