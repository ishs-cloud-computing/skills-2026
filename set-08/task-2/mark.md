# 2026년도 전국기능경기대회 채점기준

**직종명**: 클라우드컴퓨팅 (제2과제 · Small Challenges)

## 1. 채점상의 유의사항

1. 각 모듈의 리소스는 해당 모듈 요구사항에 명시된 Region에 생성한다.
2. 웹 페이지 접근은 Chrome 또는 Firefox로 진행한다.
3. Shell 명령어의 출력은 AWS CLI 버전에 따라 일부 다를 수 있다.
4. 문제지와 채점지에 있는 `<비번호>`, `<자율>` 등은 선수 제출 값으로 확인한다.
5. 채점은 문항 순서대로 진행한다.
6. 부분 점수가 있는 문항은 채점 항목에 표시된 배점만 인정한다.
7. 부분 점수가 따로 없는 문항은 조건을 모두 만족해야 점수로 인정한다.
8. 리소스 정보를 읽어오는 항목은 CloudShell에서 자동화 채점 스크립트로 조회하고, 채점위원은 출력 결과를 기준으로 판정한다.
9. 선수 이의가 있는 경우 채점위원이 동일 명령을 직접 실행하여 확인할 수 있다.
10. IAM User Access Key를 별도로 생성하여 채점하지 않는다.
11. CloudShell을 실행한 IAM User 또는 Role 권한으로 채점한다.
12. 채점 시 대기가 필요한 경우 항목당 최대 3분을 초과하지 않는다.

## 2. 채점기준표

### 1) 주요항목별 배점

| 과제번호 | 일련번호 | 주요항목 | 배점 | 채점방법(독립) | 채점방법(합의) | 채점시기(경기 진행중) | 채점시기(경기 종료후) | 비고 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 제2과제 | 1 | DocumentDB based NoSQL Application | 7.5 | O | | | O | 모듈1 |
| | 2 | Simplify Service Networking with VPC Lattice | 7.5 | O | | | O | 모듈2 |
| | 3 | Cloud Event Handling | 7.5 | O | | | O | 모듈3 |
| | 4 | Event-driven Pod Scaling with AWS SQS | 7.5 | O | | | O | 모듈4 |
| | | **합계** | **30** | | | | | |

### 2) 채점방법 및 기준

| 과제번호 | 일련번호 | 주요항목 | 세부 일련번호 | 세부항목(채점방법) | 배점 |
| --- | --- | --- | --- | --- | --- |
| 제2과제 | 1 | DocumentDB based NoSQL Application | 1 | DocumentDB Cluster 및 Instance 구성 | 1.5 |
| | | | 2 | Secret 및 Client EC2 구성 | 1.5 |
| | | | 3 | Client Application 및 데이터 적재 상태 | 1.5 |
| | | | 4 | DocumentDB Index 및 TTL 구성 | 1.5 |
| | | | 5 | NoSQL 조회 기능 검증 | 1.5 |
| | 2 | Simplify Service Networking with VPC Lattice | 1 | 기본 VPC 구성 | 1.5 |
| | | | 2 | Client/Service EC2 및 애플리케이션 구성 | 1.5 |
| | | | 3 | VPC Lattice Service Network 및 Service 구성 | 1.5 |
| | | | 4 | Target Group, Listener, Security Group 구성 | 1.5 |
| | | | 5 | End-to-End 기능 검증 | 1.5 |
| | 3 | Cloud Event Handling | 1 | 기본 VPC, EC2, Security Group 구성 | 1.5 |
| | | | 2 | 보호 대상 Security Group 기준 상태 | 1.5 |
| | | | 3 | SNS Topic 및 Lambda 구성 | 1.5 |
| | | | 4 | CloudTrail, EventBridge Rule 및 Target 구성 | 1.5 |
| | | | 5 | 최종 기능 검증 | 1.5 |
| | 4 | Event-driven Pod Scaling with AWS SQS | 1 | EKS Cluster, VPC, Fargate Profile 구성 | 1.25 |
| | | | 2 | SQS Queue 및 IAM ServiceAccount 구성 | 1.25 |
| | | | 3 | KEDA/Karpenter Controller Fargate 배포 구성 | 1.25 |
| | | | 4 | Worker Application 및 KEDA ScaledObject 구성 | 1.25 |
| | | | 5 | Karpenter NodePool, EC2NodeClass 및 Worker EC2 배치 구성 | 1.25 |
| | | | 6 | SQS 기반 Scale Out 및 처리 기능 검증 | 1.25 |
| | | | | **합계** | **30** |

### 3) 채점 내용

#### 0. 채점 준비 (배점 없음)

1) CloudShell에서 과제 채점에 필요한 기본 도구를 확인합니다.
2) `aws`, `curl`, `jq`, `kubectl` 명령이 실행 가능한지 확인합니다.
3) `kubectl`이 없는 경우 아래 명령어로 EKS Cluster 버전에 맞는 `kubectl`을 설치 후 다시 확인합니다.
4) 본 항목은 채점 준비 절차이며 배점은 없습니다.

```bash
aws --version
curl --version
jq --version
if command -v kubectl >/dev/null 2>&1; then
  kubectl version --client
else
  EKS_VERSION=$(aws eks describe-cluster --region us-west-2 --name skills-sqs-cluster --query 'cluster.version' --output text)
  KUBECTL_VERSION="v${EKS_VERSION}.0"
  curl -L -o /tmp/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
  chmod +x /tmp/kubectl
  export PATH="/tmp:$PATH"
  kubectl version --client
fi
```

※ `kubectl` 설치 명령은 CloudShell에 `kubectl`이 없을 때만 실행합니다.
※ EKS Cluster가 아직 생성되지 않은 경우 4모듈 채점 직전에 본 설치 절차를 수행합니다.
※ 채점 스크립트는 `kubectl`을 자동 설치하지 않으므로 4모듈 채점 전 본 준비 절차를 완료해야 합니다.

5) 아래 명령어를 입력하여 채점에 필요한 값을 변수로 선언합니다.
6) 값이 비어 있거나 `None`이면 해당 리소스가 요구 이름으로 생성되지 않은 것입니다.

```bash
export NOSQL_CLIENT_EC2_PUBLIC_IP=$(aws ec2 describe-instances --region ap-northeast-2 --filters Name=tag:Name,Values=skills-nosql-client-ec2 Name=instance-state-name,Values=running --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
export LATTICE_CLIENT_EC2_PUBLIC_IP=$(aws ec2 describe-instances --region ap-northeast-1 --filters Name=tag:Name,Values=skills-lattice-client-ec2 Name=instance-state-name,Values=running --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
export SERVICE_NETWORK_ID=$(aws vpc-lattice list-service-networks --region ap-northeast-1 --query "items[?name=='skills-lattice-sn'].id | [0]" --output text)
export TARGET_GROUP_ID=$(aws vpc-lattice list-target-groups --region ap-northeast-1 --query "items[?name=='skills-lattice-order-tg'].id | [0]" --output text)
export SERVICE_ID=$(aws vpc-lattice list-services --region ap-northeast-1 --query "items[?name=='skills-lattice-order-service'].id | [0]" --output text)
export SERVICE_EC2_SECURITY_GROUP_ID=$(aws ec2 describe-instances --region ap-northeast-1 --filters Name=tag:Name,Values=skills-lattice-service-ec2 Name=instance-state-name,Values=running --query "Reservations[0].Instances[0].SecurityGroups[0].GroupId" --output text)
export QUEUE_URL=$(aws sqs get-queue-url --region us-west-2 --queue-name skills-sqs-queue --query QueueUrl --output text)
```

---

### 모듈1. DocumentDB based NoSQL Application

> 본 모듈은 서울 리전(ap-northeast-2)에서 채점합니다.

#### 1-1. DocumentDB Cluster 및 Instance 구성 (배점 1.5)

1) 아래 명령어를 입력합니다.
2) DocumentDB Cluster/Instance와 KMS Key가 요구사항과 일치하는지 확인합니다.

```bash
aws docdb describe-db-clusters --region ap-northeast-2 --db-cluster-identifier skills-nosql-docdb-cluster --output table
aws docdb describe-db-instances --region ap-northeast-2 --db-instance-identifier skills-nosql-docdb-instance-1 --output table
aws kms describe-key --region ap-northeast-2 --key-id alias/skills-nosql-docdb --output table
```

#### 1-2. Secret 및 Client EC2 구성 (배점 1.5)

1) 아래 명령어를 입력합니다.
2) Secret에 `username`, `password`, `host`가 있고 Client EC2가 running 상태이며 Public IP가 있는지 확인합니다.

```bash
aws secretsmanager get-secret-value --region ap-northeast-2 --secret-id skills-nosql-docdb-secret --query SecretString --output text
aws ec2 describe-instances --region ap-northeast-2 --filters Name=tag:Name,Values=skills-nosql-client-ec2 Name=instance-state-name,Values=running --output table
```

#### 1-3. Client Application 및 데이터 적재 상태 (배점 1.5)

1) 아래 명령어를 입력합니다.
2) `/health`, `/v1/admin/summary`가 HTTP 200을 반환하고 데이터 적재 상태가 요구사항과 일치하는지 확인합니다.

```bash
curl -s -w "\nhttp_code=%{http_code}\n" http://${NOSQL_CLIENT_EC2_PUBLIC_IP}:8080/health
curl -s -w "\nhttp_code=%{http_code}\n" http://${NOSQL_CLIENT_EC2_PUBLIC_IP}:8080/v1/admin/summary
```

#### 1-4. DocumentDB Index 및 TTL 구성 (배점 1.5)

1) 아래 명령어를 입력합니다.
2) 컬렉션별 Index와 TTL 구성이 요구사항과 일치하는지 확인합니다.

```bash
curl -s -w "\nhttp_code=%{http_code}\n" http://${NOSQL_CLIENT_EC2_PUBLIC_IP}:8080/v1/admin/indexes
```

#### 1-5. NoSQL 조회 기능 검증 (배점 1.5)

1) 아래 명령어를 입력합니다.
2) 각 조회 API가 HTTP 200을 반환하고 조건에 맞는 데이터가 포함되는지 확인합니다.

```bash
curl -s -w "\nhttp_code=%{http_code}\n" http://${NOSQL_CLIENT_EC2_PUBLIC_IP}:8080/v1/orders/O-1001
curl -s -w "\nhttp_code=%{http_code}\n" http://${NOSQL_CLIENT_EC2_PUBLIC_IP}:8080/v1/customers/C001/orders
curl -s -w "\nhttp_code=%{http_code}\n" "http://${NOSQL_CLIENT_EC2_PUBLIC_IP}:8080/v1/orders/pending?from=2026-06-01T00:00:00Z&to=2026-06-08T00:00:00Z"
curl -s -w "\nhttp_code=%{http_code}\n" "http://${NOSQL_CLIENT_EC2_PUBLIC_IP}:8080/v1/products/low-stock?warehouseId=W-A"
```

---

### 모듈2. Simplify Service Networking with VPC Lattice

> 본 모듈은 도쿄 리전(ap-northeast-1)에서 채점합니다.

#### 2-1. 기본 VPC 구성 (배점 1.5)

1) 아래 명령어를 입력합니다.
2) Client/Service VPC가 존재하고 CIDR이 각각 `10.61.0.0/16`, `10.62.0.0/16`인지 확인합니다.

```bash
aws ec2 describe-vpcs --region ap-northeast-1 --filters Name=tag:Name,Values=skills-lattice-client-vpc,skills-lattice-service-vpc --output table
```

#### 2-2. Client/Service EC2 및 애플리케이션 구성 (배점 1.5) — 20260807 정정 반영

1) 아래 명령어를 입력합니다.
2) Client/Service EC2 상태, Public IP 조건, Client `/health` HTTP 200 응답을 확인합니다.

```bash
aws ec2 describe-instances --region ap-northeast-1 --filters Name=tag:Name,Values=skills-lattice-client-ec2,skills-lattice-service-ec2 Name=instance-state-name,Values=running --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`].Value|[0],Id:InstanceId,Type:InstanceType,PublicIp:PublicIpAddress,PrivateIp:PrivateIpAddress,State:State.Name}' --output table
LATTICE_CLIENT_EC2_PUBLIC_IP=$(aws ec2 describe-instances --region ap-northeast-1 --filters Name=tag:Name,Values=skills-lattice-client-ec2 Name=instance-state-name,Values=running --query 'Reservations[0].Instances[0].PublicIpAddress' --output text 2>/dev/null || true)
curl -s -m 10 -w "\nhttp_code=%{http_code}\n" "http://${LATTICE_CLIENT_EC2_PUBLIC_IP}/health"
```

#### 2-3. VPC Lattice Service Network 및 Service 구성 (배점 1.5) — 20260807 정정 반영

1) 아래 명령어를 입력합니다.
2) Service Network가 존재하고, Service, VPC Association, Service Association이 ACTIVE 상태인지 확인합니다.

```bash
SERVICE_NETWORK_ID=$(aws vpc-lattice list-service-networks --region ap-northeast-1 --query 'items[?name==`skills-lattice-sn`].id|[0]' --output text 2>/dev/null || true)
aws vpc-lattice list-service-networks --region ap-northeast-1 --query 'items[?name==`skills-lattice-sn`].{Name:name,Id:id,AssociatedVPCs:numberOfAssociatedVPCs,AssociatedServices:numberOfAssociatedServices}' --output table
aws vpc-lattice list-services --region ap-northeast-1 --query 'items[?name==`skills-lattice-order-service`].{Name:name,Id:id,Dns:dnsEntry.domainName,Status:status}' --output table
aws vpc-lattice list-service-network-vpc-associations --region ap-northeast-1 --service-network-identifier "$SERVICE_NETWORK_ID" --query 'items[].{AssociationId:id,VpcId:vpcId,Status:status}' --output table
VPC_ASSOCIATION_ID=$(aws vpc-lattice list-service-network-vpc-associations --region ap-northeast-1 --service-network-identifier "$SERVICE_NETWORK_ID" --query 'items[0].id' --output text 2>/dev/null || true)
echo "VPC_ASSOCIATION_ID=${VPC_ASSOCIATION_ID}"
aws vpc-lattice get-service-network-vpc-association --region ap-northeast-1 --service-network-vpc-association-identifier "$VPC_ASSOCIATION_ID" --query '{AssociationId:id,VpcId:vpcId,Status:status,SecurityGroupIds:securityGroupIds}' --output table
aws vpc-lattice list-service-network-service-associations --region ap-northeast-1 --service-network-identifier "$SERVICE_NETWORK_ID" --query 'items[].{ServiceId:serviceId,Status:status,Dns:dnsEntry.domainName}' --output table
```

#### 2-4. Target Group, Listener, Security Group 구성 (배점 1.5) — 20260807 정정 반영

1) 아래 명령어를 입력합니다.
2) Target Group, Target, Listener, Service EC2 Security Group 구성이 요구사항과 일치하는지 확인합니다. Service EC2 Security Group의 TCP/8080 Inbound는 VPC Lattice Managed Prefix List로 제한되어야 하며 `0.0.0.0/0` 허용 시 미충족입니다.

```bash
TARGET_GROUP_ID=$(aws vpc-lattice list-target-groups --region ap-northeast-1 --query 'items[?name==`skills-lattice-order-tg`].id|[0]' --output text 2>/dev/null || true)
SERVICE_ID=$(aws vpc-lattice list-services --region ap-northeast-1 --query 'items[?name==`skills-lattice-order-service`].id|[0]' --output text 2>/dev/null || true)
SERVICE_SG_IDS=$(aws ec2 describe-instances --region ap-northeast-1 --filters Name=tag:Name,Values=skills-lattice-service-ec2 Name=instance-state-name,Values=running --query 'Reservations[0].Instances[0].SecurityGroups[].GroupId' --output text 2>/dev/null || true)
aws vpc-lattice list-target-groups --region ap-northeast-1 --query 'items[?name==`skills-lattice-order-tg`].{Name:name,Id:id,Type:type,Port:port,Protocol:protocol,Vpc:vpcIdentifier,Status:status}' --output table
aws vpc-lattice list-targets --region ap-northeast-1 --target-group-identifier "$TARGET_GROUP_ID" --query 'items[].{Target:id,Port:port,Status:status}' --output table
aws vpc-lattice list-listeners --region ap-northeast-1 --service-identifier "$SERVICE_ID" --query 'items[?name==`skills-lattice-http-listener`].{Name:name,Id:id,Port:port,Protocol:protocol}' --output table
aws ec2 describe-security-groups --region ap-northeast-1 --group-ids $SERVICE_SG_IDS --query 'SecurityGroups[].{GroupId:GroupId,GroupName:GroupName,VpcId:VpcId,Inbound:IpPermissions}' --output json
```

#### 2-5. End-to-End 기능 검증 (배점 1.5)

1) 아래 명령어를 입력합니다.
2) Client API가 HTTP 200을 반환하고 응답 JSON에 `client=ok, service.order_id=1001, service.via=vpc-lattice`가 포함되는지 확인합니다.

```bash
curl -s -m 10 -w "\nhttp_code=%{http_code}\n" "http://${LATTICE_CLIENT_EC2_PUBLIC_IP}/v1/client/orders?id=1001"
```

---

### 모듈3. Cloud Event Handling

> 본 모듈은 싱가포르 리전(ap-southeast-1)에서 채점합니다.

#### 3-1. 기본 VPC, EC2, Security Group 구성 (배점 1.5)

1) 아래 명령어를 입력합니다.
2) VPC, EC2, 보호 대상 Security Group이 존재하고 연결 상태가 요구사항과 일치하는지 확인합니다.

```bash
aws ec2 describe-vpcs --region ap-southeast-1 --filters Name=tag:Name,Values=skills-ceh-vpc --output table
aws ec2 describe-instances --region ap-southeast-1 --filters Name=tag:Name,Values=skills-ceh-ec2 Name=instance-state-name,Values=running --output table
aws ec2 describe-security-groups --region ap-southeast-1 --filters Name=tag:Name,Values=skills-ceh-protected-sg --output table
```

#### 3-2. 보호 대상 Security Group 기준 상태 (배점 1.5)

1) 아래 명령어를 입력합니다.
2) `skills-ceh-protected-sg`의 Inbound 규칙이 0개인지 확인합니다.

```bash
aws ec2 describe-security-groups --region ap-southeast-1 --filters Name=tag:Name,Values=skills-ceh-protected-sg --query "SecurityGroups[].IpPermissions" --output json
```

#### 3-3. SNS Topic 및 Lambda 구성 (배점 1.5)

1) 아래 명령어를 입력합니다.
2) SNS Topic과 Lambda Runtime, Handler, Timeout, Environment가 요구사항과 일치하는지 확인합니다.

```bash
aws sns list-topics --region ap-southeast-1 --output table
aws lambda get-function-configuration --region ap-southeast-1 --function-name skills-ceh-remediate-fn --output table
```

#### 3-4. CloudTrail, EventBridge Rule 및 Target 구성 (배점 1.5)

1) 아래 명령어를 입력합니다.
2) CloudTrail Trail, EventBridge Rule Event Pattern, Target, Lambda Resource Policy가 요구사항과 일치하는지 확인합니다.

```bash
aws cloudtrail get-trail-status --region ap-southeast-1 --name skills-ceh-cloudtrail --output table
aws events describe-rule --region ap-southeast-1 --name skills-ceh-sg-change-rule --event-bus-name default --output json
aws events list-targets-by-rule --region ap-southeast-1 --rule skills-ceh-sg-change-rule --event-bus-name default --output table
aws lambda get-policy --region ap-southeast-1 --function-name skills-ceh-remediate-fn --query Policy --output text
```

#### 3-5. 최종 기능 검증 (배점 1.5)

1) 아래 명령어로 테스트용 Inbound 규칙(TCP/22 from 0.0.0.0/0)을 추가합니다.
2) 보호 대상 Security Group ID를 변수로 선언하고, CloudTrail 이벤트와 동일하게 `groupId`를 포함한 Payload로 Lambda를 직접 호출합니다.
3) 180초 이내 Inbound 규칙이 다시 0개가 되고 Lambda Log Group이 생성되는지 확인합니다.

```bash
export PROTECTED_SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --region ap-southeast-1 --filters Name=tag:Name,Values=skills-ceh-protected-sg --query "SecurityGroups[0].GroupId" --output text)
aws ec2 authorize-security-group-ingress --region ap-southeast-1 --group-id "$PROTECTED_SECURITY_GROUP_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0
jq -n \
  --arg sg "$PROTECTED_SECURITY_GROUP_ID" \
  '{detail:{eventName:"AuthorizeSecurityGroupIngress",requestParameters:{groupId:$sg}}}' \
  > /tmp/skills-ceh-remediate-event.json
aws lambda invoke --region ap-southeast-1 --function-name skills-ceh-remediate-fn --cli-binary-format raw-in-base64-out --payload file:///tmp/skills-ceh-remediate-event.json /tmp/skills-ceh-remediate-output.json
aws ec2 describe-security-groups --region ap-southeast-1 --group-ids "$PROTECTED_SECURITY_GROUP_ID" --query "SecurityGroups[0].IpPermissions" --output json
aws logs describe-log-groups --region ap-southeast-1 --log-group-name-prefix /aws/lambda/skills-ceh-remediate-fn --output table
```

---

### 모듈4. Event-driven Pod Scaling with AWS SQS

> 본 모듈은 오레곤 리전(us-west-2)에서 채점합니다.

#### 4-1. EKS Cluster, VPC, Fargate Profile 구성 (배점 1.25) — 20260807 정정 반영

1) 아래 명령어를 입력합니다.
2) EKS Cluster와 Fargate Profile 2개가 ACTIVE이며(각 Namespaces에 keda/karpenter 포함), CloudShell에서 `kubectl` 접근 가능한지 확인합니다. `Version`·`Role`은 채점 대상이 아니며 EKS 버전은 풀이자 지정입니다.

```bash
aws eks describe-cluster --region us-west-2 --name skills-sqs-cluster --query 'cluster.{Name:name,Status:status,Endpoint:endpoint,VpcId:resourcesVpcConfig.vpcId,Subnets:resourcesVpcConfig.subnetIds}' --output table
aws eks describe-fargate-profile --region us-west-2 --cluster-name skills-sqs-cluster --fargate-profile-name skills-sqs-fp-keda --query 'fargateProfile.{Name:fargateProfileName,Status:status,Namespaces:selectors[].namespace}' --output table
aws eks describe-fargate-profile --region us-west-2 --cluster-name skills-sqs-cluster --fargate-profile-name skills-sqs-fp-karpenter --query 'fargateProfile.{Name:fargateProfileName,Status:status,Namespaces:selectors[].namespace}' --output table
aws eks update-kubeconfig --region us-west-2 --name skills-sqs-cluster
kubectl get nodes -l eks.amazonaws.com/compute-type=fargate -o json | jq '[.items[] | {name:.metadata.name}]'
```

#### 4-2. SQS Queue 및 IAM ServiceAccount 구성 (배점 1.25)

1) 아래 명령어를 입력합니다.
2) SQS Queue와 ServiceAccount IRSA annotation이 요구사항과 일치하는지 확인합니다.

```bash
aws sqs get-queue-url --region us-west-2 --queue-name skills-sqs-queue
aws sqs get-queue-attributes --region us-west-2 --queue-url "$QUEUE_URL" --attribute-names QueueArn VisibilityTimeout --output table
kubectl get serviceaccount keda-operator -n keda -o yaml
kubectl get serviceaccount karpenter -n karpenter -o yaml
kubectl get serviceaccount sqs-worker-sa -n skills-sqs -o yaml
```

#### 4-3. KEDA/Karpenter Controller Fargate 배포 구성 (배점 1.25) — 20260807 정정 반영

1) 아래 명령어를 입력합니다.
2) KEDA/Karpenter Controller Deployment의 availableReplicas가 1 이상, 각 Pod의 phase가 Running이며 Fargate Node에서 실행되는지 확인합니다.

```bash
kubectl get deployment keda-operator -n keda -o json | jq '{name:.metadata.name, availableReplicas:(.status.availableReplicas // 0), readyReplicas:(.status.readyReplicas // 0)}'
kubectl get pods -n keda -o json | jq '[.items[] | select(.metadata.name | test("^keda-operator-")) | {name:.metadata.name, phase:.status.phase, node:.spec.nodeName}]'
kubectl get deployment karpenter -n karpenter -o json | jq '{name:.metadata.name, availableReplicas:(.status.availableReplicas // 0), readyReplicas:(.status.readyReplicas // 0)}'
kubectl get pods -n karpenter -o json | jq '[.items[] | select(.metadata.name | test("^karpenter-")) | {name:.metadata.name, phase:.status.phase, node:.spec.nodeName}]'
```

#### 4-4. Worker Application 및 KEDA ScaledObject 구성 (배점 1.25) — 20260807 정정 반영

1) 아래 명령어를 입력합니다.
2) Worker Deployment(`serviceAccountName=sqs-worker-sa`, `nodeSelector`, env), ScaledObject(`minReplicaCount=0`, `maxReplicaCount=6`, `pollingInterval<=15`, `cooldownPeriod<=30`, trigger `aws-sqs-queue`/`queueLength=2`), TriggerAuthentication(`podIdentity.provider=aws-eks`) 구성이 요구사항과 일치하는지 확인합니다.

```bash
kubectl get deployment sqs-worker -n skills-sqs -o jsonpath='name={.metadata.name}{"\n"}serviceAccountName={.spec.template.spec.serviceAccountName}{"\n"}selector={.spec.selector.matchLabels}{"\n"}podLabels={.spec.template.metadata.labels}{"\n"}nodeSelector={.spec.template.spec.nodeSelector}{"\n"}env={.spec.template.spec.containers[0].env}{"\n"}image={.spec.template.spec.containers[0].image}{"\n"}'
kubectl get scaledobject sqs-worker-scaledobject -n skills-sqs -o json | jq '{name:.metadata.name, namespace:.metadata.namespace, scaleTargetRef:.spec.scaleTargetRef, minReplicaCount:.spec.minReplicaCount, maxReplicaCount:.spec.maxReplicaCount, pollingInterval:.spec.pollingInterval, cooldownPeriod:.spec.cooldownPeriod, triggers:.spec.triggers}'
kubectl get triggerauthentication sqs-worker-trigger-auth -n skills-sqs -o json | jq '{name:.metadata.name, namespace:.metadata.namespace, podIdentity:.spec.podIdentity}'
```

#### 4-5. Karpenter NodePool, EC2NodeClass 및 Worker EC2 배치 구성 (배점 1.25) — 20260812 정정 반영

1) 아래 명령어를 입력합니다.
2) NodePool(`nodeClassRef.name=skills-sqs-nodeclass`, labels `skills-nodepool=event-worker`, `consolidationPolicy` 존재), EC2NodeClass(`role` 또는 `instanceProfile` 출력), Worker EC2 Node(`nodepool`/`skillsNodepool` 라벨, `ready=True`), Worker Pod 배치가 요구사항과 일치하는지 확인합니다. `minReplicaCount=0` 특성상 채점 시점에 Worker EC2 Node 또는 Worker Pod가 없을 수 있으며, 이 경우 4-6 Scale Out 실행 결과에서 확인된 출력을 포함해 판정할 수 있습니다.

```bash
kubectl get nodepool skills-sqs-nodepool -o json | jq '{name:.metadata.name, labels:.spec.template.metadata.labels, nodeClassRef:.spec.template.spec.nodeClassRef, requirements:.spec.template.spec.requirements, consolidationPolicy:.spec.disruption.consolidationPolicy}'
kubectl get ec2nodeclass skills-sqs-nodeclass -o json | jq '{name:.metadata.name, role:.spec.role, instanceProfile:.spec.instanceProfile, subnetSelectorTerms:.spec.subnetSelectorTerms, securityGroupSelectorTerms:.spec.securityGroupSelectorTerms, amiFamily:.spec.amiFamily}'
kubectl get nodes -l karpenter.sh/nodepool=skills-sqs-nodepool,skills-nodepool=event-worker -o json | jq '[.items[] | {name:.metadata.name, nodepool:.metadata.labels["karpenter.sh/nodepool"], skillsNodepool:.metadata.labels["skills-nodepool"], instanceType:.metadata.labels["node.kubernetes.io/instance-type"], ready:([.status.conditions[] | select(.type=="Ready")][0].status)}]'
kubectl get pods -n skills-sqs -l app=sqs-worker -o json | jq '[.items[] | {name:.metadata.name, phase:.status.phase, node:.spec.nodeName}]'
```

#### 4-6. SQS 기반 Scale Out 및 처리 기능 검증 (배점 1.25)

1) 아래 명령어로 SQS 메시지를 12개 발행합니다.
2) 180초 이내 Worker Pod와 Karpenter EC2 Worker Node가 증가하고 Queue depth가 감소하는지 확인합니다.

```bash
for i in $(seq 1 12); do aws sqs send-message --region us-west-2 --queue-url "$QUEUE_URL" --message-body "judge-$i"; done
aws sqs get-queue-attributes --region us-west-2 --queue-url "$QUEUE_URL" --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible --output table
kubectl get pods -n skills-sqs -l app=sqs-worker -o wide
kubectl get nodes -l karpenter.sh/nodepool=skills-sqs-nodepool,skills-nodepool=event-worker -o wide
```

---

> **[추적 완료] 공식 예상 출력 도착(2026-08-01)**: 판정 기준·채점 스크립트 수정 diff가
> `provided/008_chall_2nd_patched_0801.md`로 제공됨 — 항목별 판정 기준은 그 문서가 이 문서보다 우선한다.
> diff는 `mark/mark2-{1..4}.sh`에 적용 완료, 구현과의 대조 결과는 NOTES.md 함정 절 참조.
> 단, 해당 문서도 최종본 아님(대회 중 변경 가능). 마이스터넷 오류 정정 마감 2026-08-13 —
> 추가 오류 질의는 그 전에 게시판 접수(72시간 내 답변 원칙).
