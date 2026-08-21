#!/usr/bin/env bash
set -u
export AWS_PAGER=""

OUT_TXT="asgmt2_module4_check_result.txt"
exec > >(tee "$OUT_TXT") 2>&1

export PATH="$HOME/.local/bin:$PATH"

install_base_tools() {
  local packages=()
  for CMD in "$@"; do
    if ! command -v "$CMD" >/dev/null 2>&1; then
      packages+=("$CMD")
    fi
  done
  if [ "${#packages[@]}" -gt 0 ]; then
    sudo dnf install -y "${packages[@]}"
  fi
}

install_aws_cli() {
  if command -v aws >/dev/null 2>&1; then
    return 0
  fi
  local arch awscli_arch
  arch=$(uname -m)
  case "$arch" in
    x86_64) awscli_arch="x86_64" ;;
    aarch64|arm64) awscli_arch="aarch64" ;;
    *) echo "지원하지 않는 CPU 아키텍처입니다: $arch" >&2; exit 2 ;;
  esac
  mkdir -p "$HOME/.local/bin"
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${awscli_arch}.zip" -o /tmp/awscliv2.zip
  unzip -q -o /tmp/awscliv2.zip -d /tmp
  /tmp/aws/install --install-dir "$HOME/usr/local/aws-cli" --bin-dir "$HOME/.local/bin" --update
}

install_kubectl() {
  if command -v kubectl >/dev/null 2>&1; then
    return 0
  fi
  local arch kubectl_arch
  arch=$(uname -m)
  case "$arch" in
    x86_64) kubectl_arch="amd64" ;;
    aarch64|arm64) kubectl_arch="arm64" ;;
    *) echo "지원하지 않는 CPU 아키텍처입니다: $arch" >&2; exit 2 ;;
  esac
  # 최종 채점지 순번 0 은 kubectl 버전을 클러스터에서 유도한다(하드코딩 아님).
  # 조회 실패 시에만 준비본 버전으로 떨어진다.
  local eks_version kubectl_version
  eks_version=$(aws eks describe-cluster --region us-west-2 --name skills-sqs-cluster --query 'cluster.version' --output text 2>/dev/null || true)
  if [ -n "$eks_version" ] && [ "$eks_version" != "None" ]; then
    kubectl_version="v${eks_version}.0"
  else
    kubectl_version="v1.35.0"
    echo "EKS 클러스터 버전 조회 실패 — kubectl ${kubectl_version} 로 진행합니다." >&2
  fi
  mkdir -p "$HOME/.local/bin"
  curl -fsSL -o "$HOME/.local/bin/kubectl" "https://dl.k8s.io/release/${kubectl_version}/bin/linux/${kubectl_arch}/kubectl"
  chmod +x "$HOME/.local/bin/kubectl"
}

install_base_tools curl jq unzip
install_aws_cli
install_kubectl

echo "== 제2과제 4모듈 Event-driven Pod Scaling with AWS SQS 채점 출력 =="
echo

echo "[4-1] EKS Cluster, VPC, Fargate Profile 구성 (1.25점)"
aws eks describe-cluster --region us-west-2 --name skills-sqs-cluster --query 'cluster.{Name:name,Status:status,Endpoint:endpoint,VpcId:resourcesVpcConfig.vpcId,Subnets:resourcesVpcConfig.subnetIds}' --output table
aws eks describe-fargate-profile --region us-west-2 --cluster-name skills-sqs-cluster --fargate-profile-name skills-sqs-fp-keda --query 'fargateProfile.{Name:fargateProfileName,Status:status,Namespaces:selectors[].namespace}' --output table
aws eks describe-fargate-profile --region us-west-2 --cluster-name skills-sqs-cluster --fargate-profile-name skills-sqs-fp-karpenter --query 'fargateProfile.{Name:fargateProfileName,Status:status,Namespaces:selectors[].namespace}' --output table
aws eks update-kubeconfig --region us-west-2 --name skills-sqs-cluster
kubectl get nodes -l eks.amazonaws.com/compute-type=fargate -o json | jq '[.items[] | {name:.metadata.name}]'

echo
echo "[4-2] SQS Queue 및 IAM ServiceAccount 구성 (1.25점)"
QUEUE_URL=$(aws sqs get-queue-url --region us-west-2 --queue-name skills-sqs-queue --query QueueUrl --output text 2>/dev/null || true)
echo "QUEUE_URL=${QUEUE_URL}"
if [ -n "$QUEUE_URL" ] && [ "$QUEUE_URL" != "None" ]; then
  aws sqs get-queue-attributes --region us-west-2 --queue-url "$QUEUE_URL" --attribute-names QueueArn VisibilityTimeout --output table
else
  echo "skills-sqs-queue Queue URL 식별 실패"
fi
kubectl get serviceaccount keda-operator -n keda -o jsonpath='keda/keda-operator role={.metadata.annotations.eks\.amazonaws\.com/role-arn}{"\n"}'
kubectl get serviceaccount karpenter -n karpenter -o jsonpath='karpenter/karpenter role={.metadata.annotations.eks\.amazonaws\.com/role-arn}{"\n"}'
kubectl get serviceaccount sqs-worker-sa -n skills-sqs -o jsonpath='skills-sqs/sqs-worker-sa role={.metadata.annotations.eks\.amazonaws\.com/role-arn}{"\n"}'

echo
echo "[4-3] KEDA/Karpenter Controller Fargate 배포 구성 (1.25점)"
kubectl get deployment keda-operator -n keda -o json | jq '{name:.metadata.name, availableReplicas:(.status.availableReplicas // 0), readyReplicas:(.status.readyReplicas // 0)}'
kubectl get pods -n keda -o json | jq '[.items[] | select(.metadata.name | test("^keda-operator-")) | {name:.metadata.name, phase:.status.phase, node:.spec.nodeName}]'
kubectl get deployment karpenter -n karpenter -o json | jq '{name:.metadata.name, availableReplicas:(.status.availableReplicas // 0), readyReplicas:(.status.readyReplicas // 0)}'
kubectl get pods -n karpenter -o json | jq '[.items[] | select(.metadata.name | test("^karpenter-")) | {name:.metadata.name, phase:.status.phase, node:.spec.nodeName}]'

echo
echo "[4-4] Worker Application 및 KEDA ScaledObject 구성 (1.25점)"
kubectl get deployment sqs-worker -n skills-sqs -o jsonpath='name={.metadata.name}{"\n"}serviceAccountName={.spec.template.spec.serviceAccountName}{"\n"}selector={.spec.selector.matchLabels}{"\n"}podLabels={.spec.template.metadata.labels}{"\n"}nodeSelector={.spec.template.spec.nodeSelector}{"\n"}env={.spec.template.spec.containers[0].env}{"\n"}image={.spec.template.spec.containers[0].image}{"\n"}'
kubectl get scaledobject sqs-worker-scaledobject -n skills-sqs -o json | jq '{name:.metadata.name, namespace:.metadata.namespace, scaleTargetRef:.spec.scaleTargetRef, minReplicaCount:.spec.minReplicaCount, maxReplicaCount:.spec.maxReplicaCount, pollingInterval:.spec.pollingInterval, cooldownPeriod:.spec.cooldownPeriod, triggers:.spec.triggers}'
kubectl get triggerauthentication sqs-worker-trigger-auth -n skills-sqs -o json | jq '{name:.metadata.name, namespace:.metadata.namespace, podIdentity:.spec.podIdentity}'

echo
echo "[4-5] Karpenter NodePool, EC2NodeClass 및 Worker EC2 배치 구성 (1.25점)"
kubectl get nodepool skills-sqs-nodepool -o json | jq '{name:.metadata.name, labels:.spec.template.metadata.labels, nodeClassRef:.spec.template.spec.nodeClassRef, requirements:.spec.template.spec.requirements, consolidationPolicy:.spec.disruption.consolidationPolicy}'
kubectl get ec2nodeclass skills-sqs-nodeclass -o json | jq '{name:.metadata.name, role:.spec.role, instanceProfile:.spec.instanceProfile, subnetSelectorTerms:.spec.subnetSelectorTerms, securityGroupSelectorTerms:.spec.securityGroupSelectorTerms, amiFamily:.spec.amiFamily}'
kubectl get nodes -l karpenter.sh/nodepool=skills-sqs-nodepool,skills-nodepool=event-worker -o json | jq '[.items[] | {name:.metadata.name, nodepool:.metadata.labels["karpenter.sh/nodepool"], skillsNodepool:.metadata.labels["skills-nodepool"], instanceType:.metadata.labels["node.kubernetes.io/instance-type"], ready:([.status.conditions[] | select(.type=="Ready")][0].status)}]'
kubectl get pods -n skills-sqs -l app=sqs-worker -o json | jq '[.items[] | {name:.metadata.name, phase:.status.phase, node:.spec.nodeName}]'

echo
echo "[4-6] SQS 기반 Scale Out 및 처리 기능 검증 (1.25점)"
echo "주의: 본 항목은 채점기준표에 따라 SQS 메시지 12개를 생성합니다."
if [ -z "$QUEUE_URL" ] || [ "$QUEUE_URL" = "None" ]; then
  echo "skills-sqs-queue Queue URL 식별 실패"
else
  SENT=0
  for I in $(seq 1 12); do
    aws sqs send-message --region us-west-2 --queue-url "$QUEUE_URL" --message-body "judge-$I" >/dev/null 2>&1 && SENT=$((SENT + 1))
  done
  echo "sent=${SENT}"
  for T in 60 120 180; do
    sleep 60
    echo "after_${T}s"
    aws sqs get-queue-attributes --region us-west-2 --queue-url "$QUEUE_URL" --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible ApproximateNumberOfMessagesDelayed --output table
    kubectl get deployment sqs-worker -n skills-sqs
    kubectl get pods -n skills-sqs -l app=sqs-worker -o wide
    kubectl get nodes -l karpenter.sh/nodepool=skills-sqs-nodepool,skills-nodepool=event-worker -o wide
    kubectl get nodeclaims -l karpenter.sh/nodepool=skills-sqs-nodepool
  done
fi

echo
echo "Result file: ${OUT_TXT}"
