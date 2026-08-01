# Module 4 — Container Logging (Linux/macOS bash·zsh 판)

구조·순서·CloudShell 단계는 [README.md](README.md)와 동일. 본 PC 명령만 bash/zsh 로 바꿨다.

모듈 전용 터미널에서 시작:

```bash
cd module-4-container-logging
export KUBECONFIG="$PWD/kubeconfig"
PLAYER="01"   # 선수 등번호
```

재부팅·새 터미널에서 복구(클러스터 생성 이후):

```bash
export KUBECONFIG="$PWD/kubeconfig"
aws eks update-kubeconfig --name o11y-cluster --region ap-northeast-1 --kubeconfig "$KUBECONFIG"
```

### 0) [본 PC] IAM 권한 조기 검증

```bash
aws iam create-role --role-name perm-probe --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' > /dev/null \
  && aws iam delete-role --role-name perm-probe \
  || echo "STOP: IAM Role 생성 불가 — 감독 문의"
```

### 1) [본 PC] Terraform

```bash
cd terraform
terraform init
terraform apply -auto-approve
```

### 2) [본 PC] EKS 클러스터 생성 (3단계와 병렬)

블록을 하나씩 실행한다. ③까지 통과한 뒤에 ④를 실행한다.

**① 값 수집·존재 확인**

```bash
cd ../eksctl
ACCOUNT_ID=$(terraform -chdir=../terraform output -raw account_id)
VPC_ID=$(terraform -chdir=../terraform output -raw vpc_id)
PRIV_SUBNET_A=$(terraform -chdir=../terraform output -json private_subnet_ids | jq -r '."o11y-sn-priv-a"')
PRIV_SUBNET_C=$(terraform -chdir=../terraform output -json private_subnet_ids | jq -r '."o11y-sn-priv-c"')
export ACCOUNT_ID VPC_ID PRIV_SUBNET_A PRIV_SUBNET_C
# envsubst 는 unset 변수를 빈 문자열로 치환하므로 치환 전 검사 필수 (대화형 셸이라 exit 대신 STOP)
if [ -n "$ACCOUNT_ID" ] && [ -n "$VPC_ID" ] && [ -n "$PRIV_SUBNET_A" ] && [ -n "$PRIV_SUBNET_C" ]; then
  printf 'OK %s %s %s %s\n' "$ACCOUNT_ID" "$VPC_ID" "$PRIV_SUBNET_A" "$PRIV_SUBNET_C"
else
  echo "STOP: terraform output 값 누락"
fi
```

**② 치환**

```bash
# ①과 별도 블록이라 재검사 — envsubst 는 unset 을 빈 문자열로 치환해 ③이 못 잡는다
if [ -n "$ACCOUNT_ID" ] && [ -n "$VPC_ID" ] && [ -n "$PRIV_SUBNET_A" ] && [ -n "$PRIV_SUBNET_C" ]; then
  envsubst '${ACCOUNT_ID} ${VPC_ID} ${PRIV_SUBNET_A} ${PRIV_SUBNET_C}' < cluster.yaml > cluster.rendered.yaml
else
  echo "STOP: ①을 먼저 실행"
fi
```

**③ 치환 확인** — 미치환 탐지 + 값 육안 확인

```bash
if grep -q '\${' cluster.rendered.yaml; then echo "STOP: 미치환 값 존재"; else grep -nE 'id:|arn:aws' cluster.rendered.yaml; fi
```

**④ 적용**

```bash
eksctl create cluster -f cluster.rendered.yaml   # kubeconfig 는 $KUBECONFIG(모듈 경로)에 기록됨
```

### 3) [CloudShell] 이미지 빌드 & ECR push

[README.md](README.md) 3단계를 수행한다. (app.py 는 provided 원본, Dockerfile 은 app/ 수정본)

### 4) [본 PC] 노드 검증

```bash
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.labels.topology\.kubernetes\.io/zone}{"\n"}{end}' | sort -u
kubectl debug node/$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}') -it --image=busybox -- chroot /host date
```

### 5) [본 PC] k8s 렌더 + 네임스페이스·StorageClass apply

블록을 하나씩 실행한다. ③까지 통과한 뒤에 ④를 실행한다.

**① 값 수집·존재 확인**

```bash
cd ../k8s
ECR_URL=$(terraform -chdir=../terraform output -raw ecr_repository_url)
ALB_SG_ID=$(terraform -chdir=../terraform output -raw alb_sg_id)
# zsh 는 "$ECR_URL:latest" 의 :l 을 modifier 로 해석 — 중괄호 필수
export ECR_IMAGE="${ECR_URL}:latest" ALB_SG_ID
if [ -n "$ECR_URL" ] && [ -n "$ALB_SG_ID" ]; then
  printf 'OK %s %s\n' "$ECR_IMAGE" "$ALB_SG_ID"
else
  echo "STOP: terraform output 값 누락"
fi
```

**② 치환**

```bash
# ①과 별도 블록이라 재검사 — envsubst 는 unset 을 빈 문자열로 치환해 ③이 못 잡는다
if [ -n "$ECR_IMAGE" ] && [ -n "$ALB_SG_ID" ]; then
  mkdir -p rendered
  for f in *.yaml; do envsubst '${ECR_IMAGE} ${ALB_SG_ID}' < "$f" > "rendered/$f"; done
else
  echo "STOP: ①을 먼저 실행"
fi
```

**③ 치환 확인**

```bash
if grep -q '\${' rendered/*.yaml; then echo "STOP: 미치환 값 존재"; else grep -nE 'image:|groupID:' rendered/*.yaml; fi
```

**④ 적용** — 05-storageclass 는 6단계 Loki PVC 의 전제라 helm 보다 먼저 있어야 한다

```bash
kubectl apply -f rendered/00-namespace.yaml -f rendered/05-storageclass.yaml
kubectl get sc o11y-gp3
```

### 6) [본 PC] helm 설치 (LBC → Loki → Grafana)

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo add grafana-community https://grafana-community.github.io/helm-charts
helm repo update

VPC_ID=$(terraform -chdir=../terraform output -raw vpc_id)
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system --version 3.4.3 \
  --set clusterName=o11y-cluster --set region=ap-northeast-1 --set vpcId="$VPC_ID" \
  --set serviceAccount.create=false --set serviceAccount.name=aws-load-balancer-controller --wait

helm upgrade --install o11y-loki grafana-community/loki -n monitoring --version 18.7.1 -f ../helm/loki-values.yaml --wait

# 비밀번호는 작은따옴표 조각으로 감싼다 — bash 히스토리 확장(!)·zsh 모두 안전
helm upgrade --install o11y-grafana grafana-community/grafana -n monitoring --version 12.10.0 -f ../helm/grafana-values.yaml \
  --set adminUser="skills${PLAYER}" --set adminPassword='GoodJob!Skills'"${PLAYER}"'^^' \
  --set-file dashboards.default.log-overview.json=../helm/dashboards/log-overview.json --wait
```

### 7) [본 PC] k8s apply + TG healthy 확인

```bash
kubectl apply -f rendered/    # 00·05는 재적용(무해), TGB CRD 는 6단계 LBC 가 제공
kubectl get pods -n o11y && kubectl get pods -n monitoring
for tg in o11y-app-tg o11y-grafana-tg; do
  aws elbv2 describe-target-health --target-group-arn "$(aws elbv2 describe-target-groups --names $tg --query 'TargetGroups[0].TargetGroupArn' --output text --region ap-northeast-1)" --query 'TargetHealthDescriptions[].TargetHealth.State' --output text --region ap-northeast-1
done
# 기대: healthy healthy / healthy
```

### 8) [본 PC] 종단 스모크

```bash
APP_ALB=$(terraform -chdir=../terraform output -raw app_alb_dns)
curl -s "http://$APP_ALB/healthz"; echo
curl -s "http://$APP_ALB/log?level=error&count=3"; echo
# 대시보드 3색 범례(error 빨강·warn 노랑·info 초록) 확인용 — 레벨별 건수를 다르게
curl -s "http://$APP_ALB/log?level=warn&count=10"; echo
curl -s "http://$APP_ALB/log?level=info&count=30"; echo
# 별도 탭: kubectl port-forward -n monitoring svc/o11y-loki 3100:3100
curl -s -G http://localhost:3100/loki/api/v1/query_range --data-urlencode 'query={k8s_namespace_name="o11y"} | json | level="ERROR"' --data-urlencode 'limit=5'
```

Grafana 확인은 [README.md](README.md) 8단계와 동일.

### 9) [CloudShell] 접속 확인 + 셀프 채점

[README.md](README.md) 9단계를 수행한다. (access entry 추가 명령은 본 PC에서 bash 로 실행해도 동일 — 백틱 줄바꿈만 `\` 로)

## Teardown

```bash
cd k8s
kubectl delete -f rendered/40-tgb-grafana.yaml
kubectl delete -f rendered/30-tgb-app.yaml
helm uninstall o11y-grafana -n monitoring
helm uninstall o11y-loki -n monitoring
kubectl delete pvc -n monitoring --all
helm uninstall aws-load-balancer-controller -n kube-system
cd ../eksctl && eksctl delete cluster -f cluster.rendered.yaml
cd ../terraform && terraform destroy -auto-approve
```
