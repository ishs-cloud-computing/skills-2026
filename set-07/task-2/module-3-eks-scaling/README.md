# Module 3 — EKS Scaling (ap-northeast-2)

SQS + EKS 1.35 + KEDA(Pod 스케일) + Karpenter(Node 스케일). terraform·클러스터(eksctl)·헬름·kubectl 은 본 PC, **이미지 빌드만 CloudShell**(로컬 Docker 불가) 에서 한다.
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
#    https://github.com/ishs-cloud-computing/lab-bootstrap 를 받아 실행한다.
.\lab-bootstrap.ps1

# 1) terraform
#    apply 전에 과제지의 아래 이름이 terraform.tfvars·eksctl/cluster.yaml 값과 같은지 대조한다.
#    skm-order-queue / skm-eks-cluster / skm-cluster-addon-ng (+노드 태그 skm-cluster-addon-ng-node)
#    order-processor / order-scaler / skm-app-nodepool / skm-app-nodeclass
#    인스턴스 타입·노드 수는 eksctl/cluster.yaml 과 k8s/10-karpenter-nodepool.yaml 에 있다.
cd terraform
terraform init
terraform apply -auto-approve
terraform output -json > outputs.json
cd ..

# 2) cluster.yaml 토큰 치환 (CloudShell envsubst 대체) → cluster.rendered.yaml
$o = Get-Content terraform\outputs.json -Raw | ConvertFrom-Json
$map = @{
  ACCOUNT_ID            = $o.account_id.value
  REGION                = $o.region.value
  CLUSTER_NAME          = $o.cluster_name.value
  VPC_ID                = $o.vpc_id.value
  PRIV_SUBNET_A         = $o.private_subnet_ids.value.'skm-subnet-priv-a'
  PRIV_SUBNET_C         = $o.private_subnet_ids.value.'skm-subnet-priv-c'
  KARPENTER_NODE_ROLE   = $o.karpenter_node_role_name.value
  KEDA_POLICY_ARN       = $o.keda_policy_arn.value
  KARPENTER_POLICY_ARN  = $o.karpenter_controller_policy_arn.value
  APP_SQS_POLICY_ARN    = $o.app_sqs_policy_arn.value
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
kubectl get pods -n keda             # 3개 모두 Running (Pending 이면 NOTES.md 의 KEDA toleration 항목)

# 5) Karpenter 1.14.0 — kube-system (채점 3-5). CriticalAddonsOnly toleration 은 차트 기본값.
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter -n kube-system --version 1.14.0 `
  --set serviceAccount.create=false --set serviceAccount.name=karpenter `
  --set settings.clusterName=$($map.CLUSTER_NAME) `
  --set settings.interruptionQueue="" `
  --set replicas=1 `
  --set controller.resources.requests.cpu=0.5 `
  --set controller.resources.requests.memory=512Mi
kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter   # 1개 Running

# 6) k8s 오브젝트 (번호 순서대로 — NodePool 이 먼저 있어야 앱 Pod 가 스케줄된다)
#    <...> 토큰 치환 (CloudShell sed 대체). 이미지(B)는 미리 push 돼 있어야 함.
$ECR = $o.ecr_repository_url.value; $SQS = $o.sqs_queue_url.value
kubectl apply -f k8s\00-namespace.yaml
(Get-Content k8s\10-karpenter-nodepool.yaml -Raw).Replace('<CLUSTER_NAME>', $map.CLUSTER_NAME).Replace('<KARPENTER_NODE_ROLE>', $map.KARPENTER_NODE_ROLE) | kubectl apply -f -
(Get-Content k8s\20-deployment.yaml -Raw).Replace('<ECR_IMAGE>', "${ECR}:v1.0.0").Replace('<SQS_URL>', $SQS).Replace('<AWS_REGION>', $map.REGION) | kubectl apply -f -
(Get-Content k8s\30-keda-scaledobject.yaml -Raw).Replace('<SQS_URL>', $SQS).Replace('<AWS_REGION>', $map.REGION) | kubectl apply -f -

# 7) 검증 — Karpenter 가 노드 1대를 띄우고 앱 Pod 가 Ready 될 때까지 ~2분
kubectl get nodes -l karpenter.sh/nodepool=skm-app-nodepool    # 1대
kubectl get pods -n skillsmkt -o wide                          # order-processor 1/1 Running
kubectl get scaledobject -n skillsmkt                          # order-scaler READY True
```

```bash
# ===== CloudShell (ap-northeast-2) — 이미지 빌드 + 채점만 =====

# A) 반입: 제공 소스 + outputs.json 만 (eksctl/k8s 는 본 PC 에서 apply 하므로 불필요)
#    본 PC: Compress-Archive -Force -DestinationPath module-3.zip -Path ..\provided\Module3-EKS-Scaling, terraform\outputs.json
#    → CloudShell Actions → Upload file 로 module-3.zip 업로드
mkdir -p ~/module-3 && cd ~/module-3 && unzip -o ~/module-3.zip

# 환경 변수 (재접속 대비 영구화 — 작업규칙 6, CloudShell $HOME 영속)
cat > ~/.skm-env <<EOF
export AWS_DEFAULT_REGION=$(jq -r '.region.value' ~/module-3/outputs.json)
export CLUSTER_NAME=$(jq -r '.cluster_name.value' ~/module-3/outputs.json)
export ECR=$(jq -r '.ecr_repository_url.value' ~/module-3/outputs.json)
EOF
grep -qxF 'source ~/.skm-env' ~/.bashrc || echo 'source ~/.skm-env' >> ~/.bashrc
source ~/.skm-env

# B) 앱 이미지 빌드/푸시 (제공 Dockerfile 그대로, CloudShell 내장 Docker) — 본 PC 6) 전에 완료
cd ~/module-3/Module3-EKS-Scaling
aws ecr get-login-password | docker login --username AWS --password-stdin "${ECR%/*}"
docker build -t "$ECR:v1.0.0" .
docker push "$ECR:v1.0.0"

# C) 채점 — kubeconfig 를 채점 셸에 심고 실행 (root 동일 신원이라 인증 자동)
aws eks update-kubeconfig --name "$CLUSTER_NAME"
bash ~/module-3/mark/mark3.sh
# 3-6: 메시지 100건 주입 → 3분 관찰 → Max Ready Pods 5 / Max App Nodes 2 이상
# 3-7: purge → 3분 관찰 → Final Pods 1 / Final Nodes 1

# D) 과제 종료 전 부하를 모두 중지해 Pod 1 / Karpenter 노드 1 상태로 만든다 (과제지 ⚠️).
kubectl get pods -n skillsmkt
kubectl get nodes -l karpenter.sh/nodepool=skm-app-nodepool
```

## 참고

- 설계 근거: `docs/src/content/docs/setlist/set-07/task-2/deployment.md`
- 채점 항목 ↔ 구현 매핑: 같은 경로의 `mapping.md`
- 함정·미해결 항목: [../NOTES.md](../NOTES.md)
