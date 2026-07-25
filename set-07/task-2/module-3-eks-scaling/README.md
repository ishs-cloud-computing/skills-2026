# Module 3 — EKS Scaling (ap-northeast-2)

SQS + EKS 1.35 + KEDA(Pod 스케일) + Karpenter(Node 스케일). terraform·클러스터(eksctl)·헬름·kubectl 은 본 PC, **이미지 빌드만 CloudShell**(로컬 Docker 불가) 에서 한다.
`eksctl create`(~20분) 는 본 PC 에서 돌린다 — CloudShell 은 키보드 유휴 ~20–30분에 세션이 회수되어(백그라운드 프로세스는 활동으로 안 침) 장시간 create 가 죽는다. 짧은 이미지 빌드·채점만 CloudShell 에 남긴다.
본 PC 가 Linux 면 [README.linux.md](README.linux.md) 를 사용한다.

## 디렉토리 구조

```
module-3-eks-scaling/
├── terraform/            # VPC, SQS, ECR, KEDA/Karpenter/App IAM
├── eksctl/cluster.yaml   # skm-eks-cluster 1.35, addon NG(taint), IRSA, public+private endpoint
└── k8s/
    ├── 00-namespace.yaml
    ├── 10-karpenter-nodepool.yaml   # EC2NodeClass skm-app-nodeclass + NodePool skm-app-nodepool
    ├── 20-deployment.yaml           # order-processor (<ECR_IMAGE>/<SQS_URL> 치환)
    └── 30-keda-scaledobject.yaml    # order-scaler (<SQS_URL> 치환)

# 앱 소스: ../provided/Module3-EKS-Scaling/ (제공 app.py/Dockerfile, 수정 금지) — CloudShell 에서 그대로 빌드
# 채점: ../mark/mark3.sh (CloudShell 에서 실행)
```

## 배포 순서

클러스터(eksctl)·helm·kubectl 은 본 PC 에서, 이미지 빌드만 CloudShell 에서 한다. 이미지 빌드는
ECR 만 있으면 되므로(terraform 직후 존재) 본 PC 클러스터 생성과 **병행**해도 된다 — 단 본 PC 의
deployment apply(7) 전에 push(C) 가 끝나 있어야 한다.

```powershell
# ===== 본 PC (PowerShell) =====
# 0) k8s 툴 설치 (eksctl·helm·kubectl 일괄) — 이미 있으면 생략
.\lab-bootstrap.ps1

# 1) terraform
cd terraform
terraform init
terraform apply -auto-approve
terraform output -json > outputs.json
cd ..

# 2) cluster.yaml 토큰 치환 (CloudShell envsubst 대체) → cluster.rendered.yaml
$o = Get-Content terraform\outputs.json -Raw | ConvertFrom-Json
$map = @{
  ACCOUNT_ID    = $o.account_id.value
  VPC_ID        = $o.vpc_id.value
  PRIV_SUBNET_A = $o.private_subnet_ids.value.'skm-subnet-priv-a'
  PRIV_SUBNET_C = $o.private_subnet_ids.value.'skm-subnet-priv-c'
}
$t = Get-Content eksctl\cluster.yaml -Raw
foreach ($k in $map.Keys) { $t = $t -replace [regex]::Escape('${'+$k+'}'), $map[$k] }
Set-Content eksctl\cluster.rendered.yaml $t
if (Select-String -Path eksctl\cluster.rendered.yaml -Pattern '\$\{') { throw '치환 안 된 토큰 남음' }

# 3) EKS 클러스터 (~20분 — 본 PC 셸이라 유휴 회수 없음)
eksctl create cluster -f eksctl\cluster.rendered.yaml
kubectl get nodes -L dedicated       # addon 노드 1대 (dedicated=addon)

# 4) KEDA 2.20.1 — keda-operator SA 재사용(IRSA), addon 노드 taint toleration
helm repo add kedacore https://kedacore.github.io/charts; helm repo update
helm upgrade --install keda kedacore/keda -n keda --create-namespace --version 2.20.1 `
  --set serviceAccount.operator.create=false `
  --set serviceAccount.operator.name=keda-operator `
  --set 'tolerations[0].key=CriticalAddonsOnly' `
  --set 'tolerations[0].operator=Exists'
kubectl get pods -n keda             # 3개 모두 Running (Pending 이면 toleration 미적용 — 주의 참조)

# 5) Karpenter 1.14.0 — kube-system (채점 3-5). CriticalAddonsOnly toleration 은 차트 기본값.
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter -n kube-system --version 1.14.0 `
  --set serviceAccount.create=false --set serviceAccount.name=karpenter `
  --set settings.clusterName=skm-eks-cluster `
  --set settings.interruptionQueue="" `
  --set replicas=1 `
  --set controller.resources.requests.cpu=0.5 `
  --set controller.resources.requests.memory=512Mi
kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter   # 1개 Running

# 6) k8s 오브젝트 (번호 순서대로 — NodePool 이 먼저 있어야 앱 Pod 가 스케줄된다)
#    <ECR_IMAGE>/<SQS_URL> 치환 (CloudShell sed 대체). 이미지(C)는 미리 push 돼 있어야 함.
$ECR = $o.ecr_repository_url.value; $SQS = $o.sqs_queue_url.value
kubectl apply -f k8s\00-namespace.yaml
kubectl apply -f k8s\10-karpenter-nodepool.yaml
(Get-Content k8s\20-deployment.yaml -Raw).Replace('<ECR_IMAGE>', "${ECR}:v1.0.0").Replace('<SQS_URL>', $SQS) | kubectl apply -f -
(Get-Content k8s\30-keda-scaledobject.yaml -Raw).Replace('<SQS_URL>', $SQS) | kubectl apply -f -

# 7) 검증 — Karpenter 가 노드 1대를 띄우고 앱 Pod 가 Ready 될 때까지 ~2분
kubectl get nodes -l karpenter.sh/nodepool=skm-app-nodepool    # 1대
kubectl get pods -n skillsmkt -o wide                          # order-processor 1/1 Running
kubectl get scaledobject -n skillsmkt                          # order-scaler READY True
```

```bash
# ===== CloudShell (ap-northeast-2) — 이미지 빌드 + 채점만 =====
# 짧은 작업뿐이라 유휴 회수 위험 없음. task-2 공통 root 신원이라 본 PC 생성 클러스터에 바로 접근된다.

# A) 반입: 제공 소스 + outputs.json 만 (eksctl/k8s 는 본 PC 에서 apply 하므로 불필요)
#    본 PC: Compress-Archive -Force -DestinationPath module-3.zip -Path ..\provided\Module3-EKS-Scaling, terraform\outputs.json
#    → CloudShell Actions → Upload file 로 module-3.zip 업로드
mkdir -p ~/module-3 && cd ~/module-3 && unzip -o ~/module-3.zip
ECR=$(jq -r '.ecr_repository_url.value' ~/module-3/outputs.json)

# B) 앱 이미지 빌드/푸시 (제공 Dockerfile 그대로, CloudShell 내장 Docker) — 본 PC 6) 전에 완료
cd ~/module-3/Module3-EKS-Scaling
aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin "${ECR%/*}"
docker build -t "$ECR:v1.0.0" .
docker push "$ECR:v1.0.0"

# C) 채점 — kubeconfig 를 채점 셸에 심고 실행 (root 동일 신원이라 인증 자동)
aws eks update-kubeconfig --name skm-eks-cluster --region ap-northeast-2
bash ~/module-3/mark/mark3.sh
# 3-6: 메시지 100건 주입 → 3분 관찰 → Max Ready Pods 5 / Max App Nodes 2 이상
# 3-7: purge → 3분 관찰 → Final Pods 1 / Final Nodes 1
```

## 요구사항 ↔ 구현 매핑 (채점지 3)

| 항목 | 요구사항 | 구현 |
|------|----------|------|
| 3-1 | SQS `skm-order-queue` | `terraform/sqs.tf` |
| 3-2 | 클러스터 1.35 / addon NG 1/1/1 t3.medium / 노드 Name 태그 | `eksctl/cluster.yaml` |
| 3-3 | order-processor (replicas/port/requests/env, NodePool 배치) | `k8s/20-deployment.yaml` |
| 3-4 | KEDA(keda ns) + order-scaler 1~5 / qlen 5 | 배포 4) + `k8s/30-keda-scaledobject.yaml` |
| 3-5 | Karpenter(kube-system) + NodePool/NodeClass/taint/consolidation | 배포 5) + `k8s/10-karpenter-nodepool.yaml` |
| 3-6 | 스케일아웃 (Pod ≥5, Node ≥2) | `20`,`10` (500m×5 는 노드 1대에 수용 불가) |
| 3-7 | 스케일인 (Pod 1, Node 1) | `30`(scaleDown 30s) + `10`(consolidate 60s) |

## 주의 / 검증 포인트

- **이름 정확 일치**: `skm-order-queue`, `skm-eks-cluster`, `skm-cluster-addon-ng`(+노드 태그 `skm-cluster-addon-ng-node`), `order-processor`, `order-scaler`, `skm-app-nodepool`, `skm-app-nodeclass`.
- **클러스터는 본 PC 에서 root 로 생성**한다 — task-2 공통 root 신원이라 CloudShell 채점 셸 ARN 과 일치해 `update-kubeconfig` 후 kubectl 인증이 바로 된다. 만약 다른 신원으로 만들었다면 `aws eks create-access-entry` + `associate-access-policy` 로 채점 셸 IAM ARN 에 AmazonEKSClusterAdminPolicy 를 부여한다.
- deployment env 는 리터럴 3개만 유지한다(채점 3-3 이 name=value 로 정확 비교). valueFrom/추가 env 금지.
- 채점 3-7 의 대기는 최대 2.5분이다. ScaledObject 의 `stabilizationWindowSeconds: 30` 과 NodePool 의 `consolidateAfter: 60s` 를 늘리면 시간 내 1/1 수렴에 실패할 수 있다.
- KEDA 차트의 `tolerations` 값이 컴포넌트별 키로 바뀌었으면(`operator.tolerations` 등) `kubectl get pods -n keda` 가 Pending 으로 남는다. 그때는 `helm show values kedacore/keda --version 2.20.1 | grep -n -A3 tolerations` 로 현재 키를 확인해 다시 설치한다 (작업규칙 7).
- **장시간 `eksctl create`(~20분) 는 본 PC 에서** 돌린다 — CloudShell 은 키보드 유휴 ~20–30분에 VM 이 회수되며(백그라운드 프로세스·tmux 는 활동으로 치지 않아 같이 죽는다) 장시간 create 가 통보 없이 끊긴다. CloudShell 에는 짧은 이미지 빌드·채점만 남겨 이 위험을 피한다. 이미지는 push 후 ECR 에 남으므로 세션이 리셋돼도 무관하다.
- **과제 종료 전** 부하를 모두 중지해 Pod 1 / Karpenter 노드 1 상태로 만든다 (과제지 ⚠️).
