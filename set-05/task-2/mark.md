# 2026년도 전국기능경기대회 — 제2과제 채점기준

| 항목 | 내용 |
|------|------|
| 직종명 | 클라우드컴퓨팅 |

> 확인이 필요한 OCR 추정 두 곳:
> - 문제지의 SQS 안내문구 "명시되어 있지 않는 값" → 문맥상 "명시되어 있지 않은 값"으로 정리했습니다.
> - 채점기준표 3-1, 3-6-C의 인스턴스 태그가 원본에서 wsc-logging-app-bastion과 wsc-log-app-bastion으로 섞여 있는데, 원문 OCR 그대로 두었습니다(실제 채점 시 태그명 통일 필요할 수 있음).

---

## 1. 채점 시 유의사항

다음 사항을 유의하여 채점하시오.

1. AWS module은 각 지역에서 명시된 Region을 사용합니다.
2. 웹페이지 접근은 크롬이나 파이어폭스를 이용합니다.
3. 웹페이지에서 언어에 따라 문구가 다르게 보일 수 있습니다.
4. Shell에서의 명령어 출력은 버전에 따라 조금 다를 수 있습니다.
5. 문제지와 채점지에 있는 `<>`는 변수입니다. 해당 부분을 변경해 입력합니다.
6. 채점은 문항 순서대로 진행해야 합니다.
7. 삭제된 채점자료는 되돌릴 수 없으므로 유의하여 진행하며, 이의신청까지 완료 이후 선수가 생성한 클라우드 리소스를 삭제합니다.
8. 부분 점수는 존재하지 않으며, 모든 항목을 정확히 충족해야 점수로 인정됩니다.
9. 리소스의 정보를 읽어오는 채점항목은 기본적으로 스크립트 결과를 통해 채점을 진행하며, 만약 선수가 이의가 있다면 명령어를 직접 입력하여 확인해볼 수 있습니다.
10. (예상 출력)은 바로 이전 (명령어 입력)의 예상 출력을 의미합니다.
11. 채점 시에는 별도로 제공한 채점 스크립트들을 실행하여 채점할 수 있습니다. 다만 선수가 직접 입력을 원할 경우 채점기준표에 명시된 명령어 그대로 입력하여 채점할 수 있습니다.
12. 배포된 채점 스크립트 중에서 `mark1.sh`와 `mark3.sh`는 EKS를 생성해서 EKS 오브젝트를 채점해야 하므로 Bastion에서 ssh 접속 후 진행합니다.
13. 배포된 채점 스크립트 중에서 `mark2.sh` VPC Lattice 채점은 CloudShell에서 채점이 불가능하므로 Bastion에서 채점을 진행합니다.
14. Bastion에 접근 불가 시 채점이 불가하므로 반드시 SSH를 통한 접속과 권한 문제가 없도록 합니다.

---

## 2. 채점기준표

### 1) 주요항목별 배점

| 과제번호 | 일련번호 | 주요항목 | 배점 | 독립 | 합의 | 경기 진행중 | 경기 종료후 |
|----------|----------|----------|------|------|------|-------------|-------------|
| 제2과제 | 1 | EKS Scaling | 7.5 | ○ | | | ○ |
| 제2과제 | 2 | VPC Lattice | 7.5 | ○ | | | ○ |
| 제2과제 | 3 | Container Logging | 7.5 | ○ | | | ○ |
| 제2과제 | 4 | REST API Implement | 7.5 | ○ | | | ○ |
| **합계** | | | **30** | | | | |

### 2) 채점방법 및 기준

**① EKS Scaling**

| 일련번호 | 세부항목 | 배점 |
|----------|----------|------|
| 1 | 인프라 구성 | 1.0 |
| 2 | EKS 구성 | 1.0 |
| 3 | EKS NodeGroup 구성 | 1.0 |
| 4 | NameSpace 및 deployment 가용성 구성 | 1.5 |
| 5 | KEDA SQS 스케일링 설정 | 1.5 |
| 6 | KEDA 및 Karpenter Scaling 테스트 (수동채점) | 1.5 |

**② VPC Lattice**

| 일련번호 | 세부항목 | 배점 |
|----------|----------|------|
| 1 | 인프라 구성 | 1.0 |
| 2 | ALB 및 Target Group 구성 | 1.0 |
| 3 | VPC Lattice 구성 | 1.0 |
| 4 | VPC Lattice Default Rule 구성 | 1.5 |
| 5 | VPC Lattice Header Rule 구성 | 1.5 |
| 6 | Application 테스트 | 1.5 |

**③ Container Logging**

| 일련번호 | 세부항목 | 배점 |
|----------|----------|------|
| 1 | 인프라 구성 | 1.0 |
| 2 | Pod 실행 및 NLB 엔드포인트 구성 | 1.0 |
| 3 | EC2 Docker 컨테이너 실행 테스트 | 1.0 |
| 4 | Fluent Bit 서비스 실행 테스트 | 1.5 |
| 5 | E2E 로그 수집 파이프라인 테스트 | 1.5 |
| 6 | Grafana 대시보드 4종 패널 구성 (수동채점) | 1.5 |

**④ REST API Implement**

| 일련번호 | 세부항목 | 배점 |
|----------|----------|------|
| 1 | 인프라 구성 | 1.0 |
| 2 | API healthcheck 테스트 | 1.0 |
| 3 | API /v1/user 테스트 | 1.0 |
| 4 | Lambda 중복 저장 방지 테스트 | 1.5 |
| 5 | API Key 인증 동작 테스트 | 1.5 |
| 6 | API 요청 차단 확인 테스트 | 1.5 |

> **합계: 30**

---

## 3. 채점 내용

### 순번 0 — 사전 작업

**# Bastion**

1. 각 모듈에 맞게 구성한 Bastion에 접근합니다.
2. `ec2-user`로 접근합니다.
3. 아래 파일들을 각 모듈에 맞는 Bastion의 `/home/ec2-user/marking/` 디렉터리로 복사합니다.
   - `mark1.sh` — EKS Scaling
   - `mark2.sh` — VPC Lattice
   - `mark3.sh` — Container Logging
4. `/home/ec2-user/marking/` 경로에서 스크립트를 실행합니다. 실행 결과를 기반으로 채점을 진행하되, 선수가 이의를 제기할 경우 수동으로 채점을 진행할 수 있도록 합니다.
5. 채점을 진행하기 전에 다음 명령어를 수행하여 채점 진행을 위한 사전 작업을 조건에 맞게 진행합니다. (채점 스크립트 진행 시 생략 가능)

**# CloudShell**

1. CloudShell에 접근합니다.
2. `cloudshell-user`로 접근합니다.
3. 아래 파일들을 `/home/cloudshell-user/marking/` 디렉터리로 복사합니다.
   - `mark4.sh` — REST API Implement
4. `/home/cloudshell-user/marking/` 경로에서 스크립트를 실행합니다. 실행 결과를 기반으로 채점을 진행하되, 선수가 이의를 제기할 경우 수동으로 채점을 진행할 수 있도록 합니다.
5. 채점을 진행하기 전에 다음 명령어를 수행하여 채점 진행을 위한 사전 작업을 조건에 맞게 진행합니다. (채점 스크립트 진행 시 생략 가능)

```bash
# set default region of aws cli with EKS Scaling
aws configure set default.region ap-northeast-2

# set default region of aws cli with VPC Lattice
aws configure set default.region ap-southeast-1

# set default region of aws cli with Container logging
aws configure set default.region ap-northeast-1

# set default region of aws cli with REST API Implement
aws configure set default.region us-east-1
```

---

### 1. EKS Scaling

#### 1-1 인프라 구성

**(명령어 입력)**

```bash
VPC_ID=$(aws ec2 describe-vpcs \
  --region ap-northeast-2 \
  --filters "Name=tag:Name,Values=wsc-scaling-vpc" \
  --query "Vpcs[0].VpcId" \
  --output text)

aws ec2 describe-subnets \
  --region ap-northeast-2 \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "Subnets[*].[Tags[?Key=='Name']|[0].Value,AvailabilityZone,CidrBlock]" \
  --output text

aws ec2 describe-instances \
  --region ap-northeast-2 \
  --filters \
    "Name=tag:Name,Values=wsc-scaling-bastion" \
    "Name=instance-state-name,Values=running" \
  --query "Reservations[*].Instances[*].[Tags[?Key=='Name']|[0].Value,InstanceType]" \
  --output text

aws sqs list-queues \
  --query "QueueUrls[?contains(@, 'wsc-scaling-sqs')]" \
  --output text \
| awk -F'/' '{print $NF}'
```

**(예상 출력)** — 정확히 일치 (순서 상관 없음)

```
wsc-scaling-sn-pub-a   ap-northeast-2a   10.11.0.0/24
wsc-scaling-sn-pub-c   ap-northeast-2c   10.11.1.0/24
wsc-scaling-sn-priv-a  ap-northeast-2a   10.11.10.0/24
wsc-scaling-sn-priv-c  ap-northeast-2c   10.11.11.0/24
wsc-scaling-bastion    t3.medium
wsc-scaling-sqs
```

#### 1-2 EKS 구성

**(명령어 입력)**

```bash
aws eks describe-cluster \
  --region ap-northeast-2 \
  --name wsc-scaling-cluster \
  --query "cluster.{name:name,version:version}" \
  --output text
```

**(예상 출력)** — 정확히 일치

```
wsc-scaling-cluster   1.35
```

#### 1-3 EKS NodeGroup 구성

**(명령어 입력)**

```bash
aws eks describe-nodegroup \
  --region ap-northeast-2 \
  --cluster-name wsc-scaling-cluster \
  --nodegroup-name wsc-scaling-node \
  --query "nodegroup.{nodegroupName:nodegroupName, instanceTypes:join(',', instanceTypes)}" \
  --output text

aws eks describe-nodegroup \
  --region ap-northeast-2 \
  --cluster-name wsc-scaling-cluster \
  --nodegroup-name wsc-scaling-node \
  --query "nodegroup.scalingConfig" \
  --output text | tr '\t' '\n' | sort -n

aws eks describe-nodegroup \
  --region ap-northeast-2 \
  --cluster-name wsc-scaling-cluster \
  --nodegroup-name wsc-scaling-node \
  --query "nodegroup.labels.dedicated" \
  --output text
```

**(예상 출력)** — 정확히 일치

```
t3.medium   wsc-scaling-node
2
2
10
scaling
```

#### 1-4 NameSpace 및 deployment 가용성 구성

**(명령어 입력)**

```bash
kubectl get namespace wsc-scaling
kubectl get deployment wsc-scaling-deploy -n wsc-scaling
kubectl get deployment wsc-scaling-deploy -n wsc-scaling \
  -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
```

**(예상 출력)** — 빨강색 부분 정확히 일치

```
NAME          STATUS   AGE
wsc-scaling   Active   3h42m

NAME                 READY   UP-TO-DATE   AVAILABLE   AGE
wsc-scaling-deploy   2/2     2            2           3h41m

busybox:latest
```

#### 1-5 KEDA SQS 스케일링 설정

**(명령어 입력)**

```bash
kubectl get scaledobject wsc-scaling-scaledobject -n wsc-scaling \
  -o jsonpath='{.spec.pollingInterval}'; echo
kubectl get scaledobject wsc-scaling-scaledobject -n wsc-scaling \
  -o jsonpath='{.spec.triggers[0].metadata.queueLength}'; echo
```

**(예상 출력)** — 정확히 일치

```
30
5
```

#### 1-6 KEDA 및 Karpenter Scaling 테스트 (수동채점)

**(명령어 입력) — 1-6-A**

```bash
kubectl get po -n wsc-scaling
kubectl get nodes
```

**(예상 출력)** — 빨간색 부분 정확히 일치

```
NAME                                 READY   STATUS    RESTARTS   AGE
wsc-scaling-deploy-54bbd95c49-d97nd  1/1     Running   0          3m30s
wsc-scaling-deploy-54bbd95c49-vkng8  1/1     Running   0          3m30s

NAME                                              STATUS   ROLES    AGE   VERSION
ip-10-11-10-28.ap-northeast-2.compute.internal    Ready    <none>   49m   v1.35.5-eks-3385e9b
ip-10-11-11-218.ap-northeast-2.compute.internal   Ready    <none>   49m   v1.35.5-eks-3385e9b
```

**(명령어 입력) — 1-6-B** (최대 3분 대기)

```bash
SQS_URL=$(aws sqs get-queue-url \
  --queue-name wsc-scaling-sqs \
  --query 'QueueUrl' \
  --output text)

for n in {1..100}; do
  aws sqs send-message \
    --queue-url "$SQS_URL" \
    --message-body "EKS Scaling Test $n" \
    > /dev/null
  echo "EKS Scaling Test: $n"
done

sleep 60
```

**(명령어 입력) — 1-6-C**

```bash
kubectl get po -n wsc-scaling
kubectl get nodes
```

**(예상 출력)** — 빨강색 부분 정확히 일치

```
NAME                                 READY   STATUS    RESTARTS   AGE
wsc-scaling-deploy-54bbd95c49-5czr4  1/1     Running   0          12m
wsc-scaling-deploy-54bbd95c49-6w6bz  1/1     Running   0          2m38s
wsc-scaling-deploy-54bbd95c49-7swlv  1/1     Running   0          2m53s
⦁
⦁
⦁
wsc-scaling-deploy-54bbd95c49-znwz5  1/1     Running   0          2m53s
```
> Pod가 19 ~ 20개 있어야 함

```
Every 2.0s: kubectl get nodes
ip-10-11-0-47.ap-northeast-2.compute.internal: Mon May 25 06:48:37 2026

NAME                                             STATUS   ROLES    AGE     VERSION
ip-10-11-0-34.ap-northeast-2.compute.internal    Ready    <none>   7m32s   v1.35.5-eks-3385e9b
ip-10-11-1-132.ap-northeast-2.compute.internal   Ready    <none>   8m      v1.35.5-eks-3385e9b
ip-10-11-10-28.ap-northeast-2.compute.internal   Ready    <none>   30m     v1.35.5-eks-3385e9b
ip-10-11-11-218.ap-northeast-2.compute.internal  Ready    <none>   30m     v1.35.5-eks-3385e9b
```
> 기본 Node 2개 + 새로 생성된 Node 2개, 총 4개가 있어야 함

---

### 2. VPC Lattice

#### 2-1 인프라 구성

**(명령어 입력)**

```bash
aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=wsc-hub-vpc,wsc-spoke-vpc" \
  --query "Vpcs[*].[Tags[?Key=='Name']|[0].Value, CidrBlock]" \
  --output text

aws ec2 describe-subnets \
  --filters "Name=tag:Name,Values=wsc-hub-sn-pub-a,wsc-hub-sn-pub-c,wsc-spoke-sn-pub-a,wsc-spoke-sn-pub-c,wsc-spoke-sn-priv-a,wsc-spoke-sn-priv-c" \
  --query "Subnets[*].[Tags[?Key=='Name']|[0].Value, CidrBlock]" \
  --output text

aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=wsc-hub-bastion,wsc-spoke-app-v1,wsc-spoke-app-v2" \
  --query "Reservations[].Instances[].[Tags[?Key=='Name']|[0].Value,InstanceType]" \
  --output text
```

**(예상 출력)** — 정확히 일치 (순서 상관 없음)

```
wsc-hub-vpc           10.0.0.0/16
wsc-spoke-vpc         192.168.0.0/16
wsc-hub-sn-pub-a      10.0.0.0/24
wsc-hub-sn-pub-c      10.0.1.0/24
wsc-spoke-sn-pub-a    192.168.0.0/24
wsc-spoke-sn-pub-c    192.168.1.0/24
wsc-spoke-sn-priv-a   192.168.2.0/24
wsc-spoke-sn-priv-c   192.168.3.0/24
wsc-spoke-app-v1      t3.medium
wsc-spoke-app-v2      t3.medium
wsc-hub-bastion       t3.small
```

#### 2-2 ALB 및 Target Group 구성

**(명령어 입력)**

```bash
aws elbv2 describe-load-balancers \
  --names wsc-spoke-app-alb \
  --query "LoadBalancers[].[LoadBalancerName,Scheme,Type,State.Code]" \
  --output text

aws elbv2 describe-target-groups \
  --names wsc-spoke-v1-tg wsc-spoke-v2-tg \
  --query "TargetGroups[].[TargetGroupName,Protocol,Port]" \
  --output text
```

**(예상 출력)** — 정확히 일치

```
wsc-spoke-app-alb   internal   application   active
wsc-spoke-v1-tg     HTTP       8080
wsc-spoke-v2-tg     HTTP       8080
```

#### 2-3 VPC Lattice 구성

**(명령어 입력)**

```bash
aws vpc-lattice list-service-networks --query \
  "items[?name=='wsc-app-service-network'].name" --output text

aws vpc-lattice list-services --query \
  "items[?name=='wsc-app-service'].name" --output text

SERVICE_NETWORK_ID=$(aws vpc-lattice list-service-networks --query \
  "items[?name=='wsc-app-service-network'].id" --output text)

aws vpc-lattice list-service-network-vpc-associations \
  --service-network-identifier $SERVICE_NETWORK_ID --query "items[].vpcId" \
  --output text | tr '\t' '\n' | while read vpc_id; do
  aws ec2 describe-vpcs --vpc-ids $vpc_id --query \
    "Vpcs[0].Tags[?Key=='Name'].Value" --output text
done
```

**(예상 출력)** — 정확히 일치

```
wsc-app-service-network
wsc-app-service
wsc-spoke-vpc
wsc-hub-vpc
```

#### 2-4 VPC Lattice Default Rule 구성

**(명령어 입력)**

```bash
SVC_ID=$(aws vpc-lattice list-services \
  --query "items[?name=='wsc-app-service'].id" \
  --output text)

LISTENER_ID=$(aws vpc-lattice list-listeners \
  --service-identifier "$SVC_ID" \
  --query "items[0].id" \
  --output text)

for RULE_ID in $(aws vpc-lattice list-rules \
  --service-identifier "$SVC_ID" \
  --listener-identifier "$LISTENER_ID" \
  --query "items[*].id" \
  --output text); do
  RULE=$(aws vpc-lattice get-rule \
    --service-identifier "$SVC_ID" \
    --listener-identifier "$LISTENER_ID" \
    --rule-identifier "$RULE_ID" \
    --output json)
  PRIORITY=$(echo "$RULE" | jq -r '.priority')
  if [ "$PRIORITY" != "99999" ]; then
    continue
  fi
  HEADER=$(echo "$RULE" | jq -r '.match.httpMatch.headerMatches[0].match.exact // "default"')
  TARGETS=$(echo "$RULE" \
    | jq -r '.action.forward.targetGroups[] | "\(.targetGroupIdentifier):\(.weight)"' \
    | while read -r line; do
      TG_ID=$(echo "$line" | cut -d: -f1)
      WEIGHT=$(echo "$line" | cut -d: -f2)
      TG_NAME=$(aws vpc-lattice get-target-group \
        --target-group-identifier "$TG_ID" \
        --query "name" \
        --output text)
      echo -n "$TG_NAME:$WEIGHT "
    done)
  echo "Priority=$PRIORITY | Header=$HEADER | Targets=$TARGETS"
done
```

**(예상 출력)** — 정확히 일치 (순서 상관 없음)

```
Priority=99999 | Header=default | Targets=wsc-spoke-v1-tg:90 wsc-spoke-v2-tg:10
```

#### 2-5 VPC Lattice Header Rule 구성

**(명령어 입력)**

```bash
for RULE_ID in $(aws vpc-lattice list-rules --service-identifier $SVC_ID \
  --listener-identifier $LISTENER_ID --query "items[*].id" --output text); do
  RULE=$(aws vpc-lattice get-rule --service-identifier $SVC_ID \
    --listener-identifier $LISTENER_ID --rule-identifier $RULE_ID --output json)
  PRIORITY=$(echo $RULE | jq -r '.priority')
  if [ "$PRIORITY" = "99999" ]; then continue; fi
  HEADER=$(echo $RULE | jq -r '.match.httpMatch.headerMatches[0].match.exact // "default"')
  TARGETS=$(echo $RULE | jq -r '.action.forward.targetGroups[] | "\(.targetGroupIdentifier):\(.weight)"' | while read line; do
    TG_ID=$(echo $line | cut -d: -f1)
    WEIGHT=$(echo $line | cut -d: -f2)
    TG_NAME=$(aws vpc-lattice get-target-group --target-group-identifier $TG_ID --query "name" --output text)
    echo -n "$TG_NAME:$WEIGHT "
  done)
  echo "Priority=$PRIORITY | Header=$HEADER | Targets=$TARGETS"
done
```

**(예상 출력)** — 정확히 일치 (순서 상관 없음)

```
Priority=20 | Header=v2 | Targets=wsc-spoke-v2-tg:100
Priority=10 | Header=v1 | Targets=wsc-spoke-v1-tg:100
```

#### 2-6 Application 테스트

**(명령어 입력)**

```bash
for TG_NAME in wsc-spoke-v1-tg wsc-spoke-v2-tg; do
  TG_ARN=$(aws elbv2 describe-target-groups \
    --names "$TG_NAME" \
    --query "TargetGroups[0].TargetGroupArn" \
    --output text)
  STATUS=$(aws elbv2 describe-target-health \
    --target-group-arn "$TG_ARN" \
    --query "TargetHealthDescriptions[0].TargetHealth.State" \
    --output text)
  echo "$TG_NAME $STATUS"
done

SVC_ID=$(aws vpc-lattice list-services \
  --query "items[?name=='wsc-app-service'].id" \
  --output text)

LATTICE_DNS=$(aws vpc-lattice get-service \
  --service-identifier "$SVC_ID" \
  --query "dnsEntry.domainName" \
  --output text)

curl -s -H "version: v1" http://$LATTICE_DNS/version
curl -s -H "version: v2" http://$LATTICE_DNS/version
```

**(예상 출력)** — 정확히 일치

```
wsc-spoke-v1-tg healthy
wsc-spoke-v2-tg healthy
{"version":"v1"}
{"version":"v2"}
```

---

### 3. Container Logging

#### 3-1 인프라 구성

**(명령어 입력)**

```bash
aws ec2 describe-vpcs \
  --region ap-northeast-1 \
  --filters "Name=tag:Name,Values=wsc-logging-vpc" \
  --query "Vpcs[0].CidrBlock" --output text

aws ec2 describe-subnets \
  --region ap-northeast-1 \
  --filters "Name=tag:Name,Values=wsc-logging-sn-pub-a,wsc-logging-sn-pub-c,wsc-logging-sn-priv-a,wsc-logging-sn-priv-c" \
  --query "Subnets[*].[Tags[?Key=='Name'].Value|[0],CidrBlock]" \
  --output text

aws eks describe-cluster \
  --region ap-northeast-1 \
  --name wsc-logging-cluster \
  --query "cluster.[name,version]" \
  --output text

aws eks describe-nodegroup \
  --region ap-northeast-1 \
  --cluster-name wsc-logging-cluster \
  --nodegroup-name wsc-logging-ng \
  --query "nodegroup.[nodegroupName,scalingConfig]" \
  --output json
```

**(예상 출력)** — 빨강색 부분 정확히 일치 (순서 상관 없음)

```
10.3.0.0/16
wsc-logging-sn-pub-a    10.3.0.0/24
wsc-logging-sn-priv-a   10.3.2.0/24
wsc-logging-sn-pub-c    10.3.1.0/24
wsc-logging-sn-priv-c   10.3.3.0/24
wsc-logging-cluster     1.35
[
  "wsc-logging-ng",
  {
    "minSize": 2,
    "maxSize": 4,
    "desiredSize": 2
  }
]
```

#### 3-2 Pod 실행 및 NLB 엔드포인트 구성

**(명령어 입력)**

```bash
kubectl get pods -n wsc-logging -l app.kubernetes.io/name=loki,app.kubernetes.io/component=single-binary | awk '{ print $3 }'
kubectl get svc -n wsc-logging -l app.kubernetes.io/name=loki | grep LoadBalancer | awk '{ print $4 }'
kubectl get pods -n wsc-logging -l app.kubernetes.io/name=grafana | awk '{ print $3 }'
kubectl get svc -n wsc-logging -l app.kubernetes.io/name=grafana | grep LoadBalancer | awk '{ print $4 }'
```

**(예상 출력)** — 빨강색 부분 정확히 일치

```
STATUS
Running
a11c8436181b54e69aa5f34ec1e16b62-733c9ef8646d3165.elb.ap-northeast-1.amazonaws.com
STATUS
Running
a2c92ca29c5894aacb5662f1e6e3710f-92fe7d5e9f9ba881.elb.ap-northeast-1.amazonaws.com
```

#### 3-3 EC2 Docker 컨테이너 실행 테스트

**(명령어 입력)**

```bash
EC2_IP=$(aws ec2 describe-instances \
  --region ap-northeast-1 \
  --filters "Name=tag:Name,Values=wsc-logging-app-bastion" \
    "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].PublicIpAddress" --output text)

curl -s "http://$EC2_IP:5000/health"
```

**(예상 출력)** — 정확히 일치

```
{"status":"ok"}
```

#### 3-4 Fluent Bit 서비스 실행 테스트

**(명령어 입력)**

```bash
INSTANCE_ID=$(aws ec2 describe-instances \
  --region ap-northeast-1 \
  --filters "Name=tag:Name,Values=wsc-logging-app-bastion" \
  --query "Reservations[0].Instances[0].InstanceId" --output text)

CMD_ID=$(aws ssm send-command \
  --region ap-northeast-1 \
  --instance-ids $INSTANCE_ID \
  --document-name "AWS-RunShellScript" \
  --parameters '{"commands":["systemctl is-active fluent-bit"]}' \
  --query "Command.CommandId" --output text)

sleep 5

aws ssm get-command-invocation \
  --region ap-northeast-1 \
  --command-id $CMD_ID --instance-id $INSTANCE_ID \
  --query "StandardOutputContent" --output text
```

**(예상 출력)** — 정확히 일치

```
active
```

#### 3-5 E2E 로그 수집 파이프라인 테스트

**(명령어 입력) — 3-5-A** (10초 대기 후 3-5-B 입력)

```bash
EC2_IP=$(aws ec2 describe-instances \
  --region ap-northeast-1 \
  --filters "Name=tag:Name,Values=wsc-logging-app-bastion" \
    "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].PublicIpAddress" --output text)

sleep 10
curl -s "http://$EC2_IP:5000/generate?count=30" > /dev/null 2>&1
```

**(명령어 입력) — 3-5-B**

```bash
LOKI_LB=$(kubectl get svc -n wsc-logging -l app.kubernetes.io/name=loki | grep LoadBalancer | awk '{ print $4 }')

curl -sG "http://$LOKI_LB:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={namespace="wsc-app-log"}' \
  --data-urlencode 'limit=10' \
| python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('data',{}).get('result',[])), 'streams found')"
```

**(예상 출력)** — 정확히 일치

```
3 streams found    <- 1개 이상 떠야 함
```

#### 3-6 Grafana 대시보드 4종 패널 구성 (수동채점)

**(명령어 입력) — 3-6-A** (비번호를 입력하시오)

```bash
GRAFANA_LB=$(kubectl get svc -n wsc-logging -l app.kubernetes.io/name=grafana | grep LoadBalancer | awk '{ print $4 }')

read -s -p "비번호를 입력하시오: " NM
curl -s -u wsc2026-admin-$NM:admin$NM! \
  "http://$GRAFANA_LB/api/search?type=dash-db" \
  | python3 -c "import sys,json; print(len(json.load(sys.stdin)), 'dashboards')"
```

**(예상 출력)** — 정확히 일치

```
1 dashboards    <- 1개 이상 떠야 함
```

**3-6-B 브라우저 접속**

`kubectl get svc -n wsc-logging -l app.kubernetes.io/name=grafana | grep LoadBalancer | awk '{ print $4}'`에 출력된 값을 복사합니다.

Grafana(`http://<위에서 출력된 DNS 값>`)으로 접속합니다. 아이디는 `wsc2026-admin-{비번호}`를 입력하며, 비밀번호는 `admin{비번호}!`를 사용합니다.

왼쪽 Dashboards 탭을 눌러 **WSC2026 Container Logs**에 접근합니다. 아래 4종 패널이 모두 구성이 되었는지 확인합니다. (각 패널 마우스 올린 후 우측 상단 `:` 클릭)

**query 테스트** — `Inspect > Query` 클릭 후 Log Query 확인. 총 4개의 Query 확인:

```logql
{namespace="wsc-app-log"}
# 로그 스트림 출력 확인

count_over_time({namespace="wsc-app-log"} |= "INFO" [1m])
# 시계열 그래프 출력 확인

count_over_time({namespace="wsc-app-log"} |= "ERROR" [1m])
# 시계열 그래프 출력 확인

count_over_time({namespace="wsc-app-log"} |= "WARNING" [1m])
# 시계열 그래프 출력 확인
```

**(명령어 입력) — 3-6-C** (최대 15초 대기)

```bash
EC2_IP=$(aws ec2 describe-instances \
  --region ap-northeast-1 \
  --filters "Name=tag:Name,Values=wsc-logging-app-bastion" \
    "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].PublicIpAddress" --output text)

curl -s "http://$EC2_IP:5000/"
curl -s "http://$EC2_IP:5000/health"
curl -s "http://$EC2_IP:5000/generate?count=30" | jq | grep generated
```

**(예상 출력)** — 정확히 일치

```
{"service": "m3-log-generator", "status": "healthy"}
{"status": "ok"}
"generated": 30,
```

---

### 4. REST API Implement

#### 4-1 인프라 구성

**(명령어 입력)**

```bash
aws apigateway get-rest-apis \
  --query "items[?name=='wsc-rest-api'].name" \
  --output text

aws apigateway get-stages \
  --rest-api-id $(aws apigateway get-rest-apis \
    --query "items[?name=='wsc-rest-api'].id" \
    --output text) \
  --query "item[?stageName=='prod'].stageName" \
  --output text

aws lambda get-function-configuration \
  --function-name wsc-rest-function \
  --query '{LambdaName:FunctionName}' \
  --output text

aws lambda get-function-configuration \
  --function-name wsc-rest-function \
  --query 'Runtime' \
  --output text

aws dynamodb list-tables \
  --query "TableNames[?@=='wsc-rest-table']" \
  --output text
```

**(예상 출력)** — 정확히 일치

```
wsc-rest-api
prod
wsc-rest-function
python3.14
wsc-rest-table
```

#### 4-2 API healthcheck 테스트

**(명령어 입력)**

```bash
API_URL=$(aws apigateway get-rest-apis --region us-east-1 --query 'items[?name==`wsc-rest-api`].id' --output text)
API_KEY=$(aws apigateway get-api-keys --region us-east-1 --include-values --query 'items[?name==`wsc-rest-api-key`].value' --output text)

curl https://$API_URL.execute-api.us-east-1.amazonaws.com/prod/v1/healthcheck
```

**(예상 출력)** — 정확히 일치

```
{"status":"ok"}
```

#### 4-3 API /v1/user 테스트

**(명령어 입력)**

```bash
API_KEY=$(aws apigateway get-api-keys \
  --region us-east-1 \
  --include-values \
  --query "items[?name=='wsc-rest-api-key'].value" \
  --output text)

aws dynamodb scan --table-name wsc-rest-table --projection-expression "#n" --expression-attribute-names '{"#n":"name"}' | jq -c '.Items[]' | while read item; do
  aws dynamodb delete-item --table-name wsc-rest-table --key "$item" > /dev/null
done

curl -X POST https://$API_URL.execute-api.us-east-1.amazonaws.com/prod/v1/user \
  -H "x-api-key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name": "kim", "age": 19, "country": "korea"}'

curl "https://$API_URL.execute-api.us-east-1.amazonaws.com/prod/v1/user?name=kim&age=19" \
  -H "x-api-key: $API_KEY"
```

**(예상 출력)** — 정확히 일치

```
{"message": "User created successfully"}
{"name": "kim", "country": "korea", "age": 19}
```

#### 4-4 Lambda 중복 저장 방지 테스트

**(명령어 입력)**

```bash
curl -X POST https://$API_URL.execute-api.us-east-1.amazonaws.com/prod/v1/user \
  -H "x-api-key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name": "kim", "age": 19, "country": "korea"}'

curl "https://$API_URL.execute-api.us-east-1.amazonaws.com/prod/v1/user?name=nobody&age=19" \
  -H "x-api-key: $API_KEY"
```

**(예상 출력)** — 정확히 일치

```
{"message": "User already exists"}
{"message": "User not found"}
```

#### 4-5 API Key 인증 동작 테스트

**(명령어 입력)**

```bash
curl -X POST https://$API_URL.execute-api.us-east-1.amazonaws.com/prod/v1/user \
  -H "Content-Type: application/json" \
  -d '{"name": "kim", "age": 19, "country": "korea"}'
```

**(예상 출력)** — 정확히 일치

```
{"message":"Forbidden"}
```

#### 4-6 API 요청 차단 확인 테스트

**(명령어 입력)**

```bash
curl "https://$API_URL.execute-api.us-east-1.amazonaws.com/prod/v1/user?name=nobody" \
  -H "x-api-key: $API_KEY"
```

**(예상 출력)** — 정확히 일치

```
{"message": "Missing required request parameters: [age]"}
```