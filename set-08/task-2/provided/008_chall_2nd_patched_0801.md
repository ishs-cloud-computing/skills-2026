
## 순번 0. 채점 환경 사전 준비

```bash
export PATH="$HOME/.local/bin:$PATH"

ARCH=$(uname -m)
case "$ARCH" in
  x86_64)
    KUBECTL_ARCH="amd64"
    AWSCLI_ARCH="x86_64"
    ;;
  aarch64|arm64)
    KUBECTL_ARCH="arm64"
    AWSCLI_ARCH="aarch64"
    ;;
  *)
    echo "지원하지 않는 CPU 아키텍처입니다: $ARCH"
    exit 2
    ;;
esac

if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1 || ! command -v grep >/dev/null 2>&1 || ! command -v unzip >/dev/null 2>&1; then
  sudo dnf install -y curl jq grep unzip
fi

if ! command -v kubectl >/dev/null 2>&1; then
  mkdir -p "$HOME/.local/bin"
  curl -L -o "$HOME/.local/bin/kubectl" "https://dl.k8s.io/release/v1.35.0/bin/linux/${KUBECTL_ARCH}/kubectl"
  chmod +x "$HOME/.local/bin/kubectl"
fi

if ! command -v aws >/dev/null 2>&1; then
  curl "https://awscli.amazonaws.com/awscli-exe-linux-${AWSCLI_ARCH}.zip" -o "awscliv2.zip"
  unzip -q awscliv2.zip
  ./aws/install --install-dir "$HOME/usr/local/aws-cli" --bin-dir "$HOME/.local/bin" --update
fi

aws --version
curl --version
jq --version
grep --version
unzip -v | head -n 1
kubectl version --client
aws sts get-caller-identity --output table
```

```text
aws, curl, jq, grep, unzip, kubectl 명령이 실행 가능해야 하며 AWS 인증 주체가 출력되어야 합니다.
1모듈은 aws, jq, curl 명령이 필요합니다.
2모듈은 aws, curl 명령이 필요합니다.
3모듈은 aws, jq, grep 명령이 필요합니다.
4모듈은 aws, kubectl, jq 명령이 필요합니다.
본 항목은 배점하지 않으며, 도구가 없거나 인증/접근이 실패하면 해당 모듈 채점 스크립트를 정상 실행할 수 없습니다.
```

## 모듈 1. DocumentDB based NoSQL Application

## 채점 1-1

### 채점 명령어

```bash
aws docdb describe-db-clusters --region ap-northeast-2 --db-cluster-identifier skills-nosql-docdb-cluster --query 'DBClusters[0].{Cluster:DBClusterIdentifier,Status:Status,Engine:Engine,Version:EngineVersion,Encrypted:StorageEncrypted,KmsKeyId:KmsKeyId,BackupRetention:BackupRetentionPeriod,Endpoint:Endpoint,Port:Port}' --output table
aws docdb describe-db-instances --region ap-northeast-2 --db-instance-identifier skills-nosql-docdb-instance-1 --query 'DBInstances[0].{Instance:DBInstanceIdentifier,Status:DBInstanceStatus,Class:DBInstanceClass,Engine:Engine,Cluster:DBClusterIdentifier,AZ:AvailabilityZone}' --output table
aws kms describe-key --region ap-northeast-2 --key-id alias/skills-nosql-docdb --query 'KeyMetadata.{Arn:Arn,Enabled:Enabled,KeyManager:KeyManager,KeyUsage:KeyUsage}' --output table
```

### 판정 기준

```text
Cluster=skills-nosql-docdb-cluster, Status=available, Engine=docdb, Encrypted=True, Port=27017, BackupRetention>=1인지 확인합니다.
Instance=skills-nosql-docdb-instance-1, Status=available, Class=db.t3.medium, Cluster=skills-nosql-docdb-cluster인지 확인합니다.
KMS Key는 alias/skills-nosql-docdb로 조회되며 Enabled=True, KeyManager=CUSTOMER인지 확인합니다.
```

## 채점 1-2

### 채점 명령어

```bash
aws secretsmanager describe-secret --region ap-northeast-2 --secret-id skills-nosql-docdb-secret --query '{Name:Name,ARN:ARN,KmsKeyId:KmsKeyId}' --output table
aws secretsmanager get-secret-value --region ap-northeast-2 --secret-id skills-nosql-docdb-secret --query SecretString --output text | jq -r '{username, host, password_set:(.password != null and .password != "")}'
aws ec2 describe-instances --region ap-northeast-2 --filters Name=tag:Name,Values=skills-nosql-client-ec2 Name=instance-state-name,Values=running --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`].Value|[0],InstanceId:InstanceId,State:State.Name,Type:InstanceType,PublicIp:PublicIpAddress}' --output table
```

### 판정 기준

```text
Secret Name=skills-nosql-docdb-secret이고 SecretString 출력에 username, host, password_set=true가 있어야 합니다.
host는 DocumentDB Cluster Endpoint Hostname이어야 하며 Scheme 또는 Port가 포함되면 안 됩니다.
Client EC2 Name=skills-nosql-client-ec2, State=running, PublicIp가 존재해야 합니다.
```

## 채점 1-3

### 채점 명령어

```bash
curl -s -m 10 -w "\nhttp_code=%{http_code}\n" "http://${NOSQL_CLIENT_EC2_PUBLIC_IP}:8080/health"
curl -s -m 10 -w "\nhttp_code=%{http_code}\n" "http://${NOSQL_CLIENT_EC2_PUBLIC_IP}:8080/v1/admin/summary"
```

### 판정 기준

```text
/health의 http_code=200이고 status=ok, database=skills_retail, port=27017, tls=true가 출력되어야 합니다.
/v1/admin/summary의 http_code=200이고 counts.orders>=8, counts.products>=6, counts.sessions>=3이어야 합니다.
dateFieldTypes에 orders.createdAt, orders.dueAt, products.updatedAt, sessions.lastSeen, sessions.expiresAt이 날짜 타입으로 표시되어야 합니다.
```

## 채점 1-4

### 채점 명령어

```bash
curl -s -m 10 -w "\nhttp_code=%{http_code}\n" "http://${NOSQL_CLIENT_EC2_PUBLIC_IP}:8080/v1/admin/indexes"
```

### 판정 기준

```text
http_code=200이어야 합니다.
orders에는 {orderId:1} unique, {customerId:1, createdAt:-1}, {status:1, dueAt:1} Index가 있어야 합니다.
products에는 {productId:1} unique, {warehouseId:1, stock:1} Index가 있어야 합니다.
sessions에는 {sessionId:1} unique, {expiresAt:1} TTL expireAfterSeconds=0, {customerId:1, lastSeen:-1} Index가 있어야 합니다.
Index 이름은 채점하지 않습니다.
```

## 채점 1-5

### 채점 명령어

```bash
curl -s -m 10 -w "\nhttp_code=%{http_code}\n" "http://${NOSQL_CLIENT_EC2_PUBLIC_IP}:8080/v1/orders/O-1001"
curl -s -m 10 -w "\nhttp_code=%{http_code}\n" "http://${NOSQL_CLIENT_EC2_PUBLIC_IP}:8080/v1/customers/C001/orders"
curl -s -m 10 -w "\nhttp_code=%{http_code}\n" "http://${NOSQL_CLIENT_EC2_PUBLIC_IP}:8080/v1/orders/pending?from=2026-06-01T00:00:00Z&to=2026-06-08T00:00:00Z"
curl -s -m 10 -w "\nhttp_code=%{http_code}\n" "http://${NOSQL_CLIENT_EC2_PUBLIC_IP}:8080/v1/products/low-stock?warehouseId=W-A"
```

### 판정 기준

```text
모든 조회 API의 http_code=200이어야 합니다.
응답 데이터는 retail_dataset.json 기준으로 다음을 만족해야 합니다.
O-1001 조회: orderId=O-1001, customerId=C001, status=PENDING, warehouseId=W-A
C001 주문 조회: O-1006, O-1001, O-1004 포함
기간 내 PENDING 조회: O-1001, O-1003, O-1006 포함
W-A Low Stock 조회: P-BLU-003, P-RED-001 포함 및 P-GRN-002 미포함
```

## 모듈 2. VPC Lattice

## 채점 2-1

### 채점 명령어

```bash
aws ec2 describe-vpcs --region ap-northeast-1 --filters Name=tag:Name,Values=skills-lattice-client-vpc,skills-lattice-service-vpc --query 'Vpcs[].{Name:Tags[?Key==`Name`].Value|[0],VpcId:VpcId,Cidr:CidrBlock,State:State}' --output table
```

### 판정 기준

```text
skills-lattice-client-vpc의 Cidr=10.61.0.0/16, State=available이어야 합니다.
skills-lattice-service-vpc의 Cidr=10.62.0.0/16, State=available이어야 합니다.
```

## 채점 2-2

### 채점 명령어

```bash
aws ec2 describe-instances --region ap-northeast-1 --filters Name=tag:Name,Values=skills-lattice-client-ec2,skills-lattice-service-ec2 Name=instance-state-name,Values=running --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`].Value|[0],Id:InstanceId,Type:InstanceType,PublicIp:PublicIpAddress,PrivateIp:PrivateIpAddress,State:State.Name}' --output table
curl -s -m 10 -w "\nhttp_code=%{http_code}\n" "http://${LATTICE_CLIENT_EC2_PUBLIC_IP}/health"
```

### 판정 기준

```text
skills-lattice-client-ec2와 skills-lattice-service-ec2가 State=running이어야 합니다.
skills-lattice-client-ec2는 PublicIp가 존재해야 하고, skills-lattice-service-ec2는 PublicIp가 없어야 합니다.
Client /health 응답의 http_code=200이고 status=ok, app=client가 포함되어야 합니다.
```

## 채점 2-3

### 채점 명령어

```bash
aws vpc-lattice list-service-networks --region ap-northeast-1 --query 'items[?name==`skills-lattice-sn`].{Name:name,Id:id,AssociatedVPCs:numberOfAssociatedVPCs,AssociatedServices:numberOfAssociatedServices}' --output table
aws vpc-lattice list-services --region ap-northeast-1 --query 'items[?name==`skills-lattice-order-service`].{Name:name,Id:id,Dns:dnsEntry.domainName,Status:status}' --output table
aws vpc-lattice list-service-network-vpc-associations --region ap-northeast-1 --service-network-identifier "$SERVICE_NETWORK_ID" --query 'items[].{AssociationId:id,VpcId:vpcId,Status:status}' --output table
aws vpc-lattice get-service-network-vpc-association --region ap-northeast-1 --service-network-vpc-association-identifier "$VPC_ASSOCIATION_ID" --query '{AssociationId:id,VpcId:vpcId,Status:status,SecurityGroupIds:securityGroupIds}' --output table
aws vpc-lattice list-service-network-service-associations --region ap-northeast-1 --service-network-identifier "$SERVICE_NETWORK_ID" --query 'items[].{ServiceId:serviceId,Status:status,Dns:dnsEntry.domainName}' --output table
```

### 판정 기준

```text
Service Network Name=skills-lattice-sn이 존재해야 합니다.
Service Name=skills-lattice-order-service가 존재하고 Status=ACTIVE이며 Dns가 출력되어야 합니다.
Client VPC Association의 Status=ACTIVE이어야 합니다.
Service Association의 Status=ACTIVE이어야 합니다.
```

## 채점 2-4

### 채점 명령어

```bash
aws vpc-lattice list-target-groups --region ap-northeast-1 --query 'items[?name==`skills-lattice-order-tg`].{Name:name,Id:id,Type:type,Port:port,Protocol:protocol,Vpc:vpcIdentifier,Status:status}' --output table
aws vpc-lattice list-targets --region ap-northeast-1 --target-group-identifier "$TARGET_GROUP_ID" --query 'items[].{Target:id,Port:port,Status:status}' --output table
aws vpc-lattice list-listeners --region ap-northeast-1 --service-identifier "$SERVICE_ID" --query 'items[?name==`skills-lattice-http-listener`].{Name:name,Id:id,Port:port,Protocol:protocol}' --output table
aws ec2 describe-security-groups --region ap-northeast-1 --group-ids $SERVICE_SG_IDS --query 'SecurityGroups[].{GroupId:GroupId,GroupName:GroupName,VpcId:VpcId,Inbound:IpPermissions}' --output json
```

### 판정 기준

```text
Target Group Name=skills-lattice-order-tg, Type=INSTANCE, Protocol=HTTP, Port=8080이어야 합니다.
Target은 skills-lattice-service-ec2 Instance이고 Status=HEALTHY이어야 합니다.
Listener Name=skills-lattice-http-listener, Protocol=HTTP, Port=80이어야 합니다.
Service EC2 Security Group의 TCP/8080 Inbound는 VPC Lattice Managed Prefix List로 제한되어야 하며 0.0.0.0/0 허용 시 미충족입니다.
```

## 채점 2-5

### 채점 명령어

```bash
curl -s -m 10 -w "\nhttp_code=%{http_code}\n" "http://${LATTICE_CLIENT_EC2_PUBLIC_IP}/v1/client/orders?id=1001"
```

### 판정 기준

```text
http_code=200이어야 합니다.
응답 JSON에 client=ok, service.order_id=1001, service.via=vpc-lattice가 포함되어야 합니다.
```

## 모듈 3. Cloud Event Handling

## 채점 3-1

### 채점 명령어

```bash
aws ec2 describe-vpcs --region ap-southeast-1 --filters Name=tag:Name,Values=skills-ceh-vpc --query 'Vpcs[].{Name:Tags[?Key==`Name`].Value|[0],VpcId:VpcId,Cidr:CidrBlock}' --output table
aws ec2 describe-instances --region ap-southeast-1 --filters Name=tag:Name,Values=skills-ceh-ec2 Name=instance-state-name,Values=running --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`].Value|[0],Id:InstanceId,Type:InstanceType,State:State.Name,SecurityGroups:SecurityGroups[].GroupId}' --output table
aws ec2 describe-security-groups --region ap-southeast-1 --filters Name=tag:Name,Values=skills-ceh-protected-sg --query 'SecurityGroups[].{Name:Tags[?Key==`Name`].Value|[0],GroupId:GroupId,GroupName:GroupName,VpcId:VpcId}' --output table
```

### 판정 기준

```text
VPC Name=skills-ceh-vpc, Cidr=10.73.0.0/16이어야 합니다.
EC2 Name=skills-ceh-ec2, State=running이어야 합니다.
Security Group Name=skills-ceh-protected-sg가 존재하고 EC2에 연결되어 있어야 합니다.
```

## 채점 3-2

### 채점 명령어

```bash
aws ec2 describe-security-groups --region ap-southeast-1 --filters Name=tag:Name,Values=skills-ceh-protected-sg --query 'SecurityGroups[].{GroupId:GroupId,Inbound:IpPermissions,Outbound:IpPermissionsEgress}' --output json
```

### 판정 기준

```text
Inbound 또는 IpPermissions가 빈 배열 []이어야 합니다.
```

## 채점 3-3

### 채점 명령어

```bash
aws sns list-topics --region ap-southeast-1 --query 'Topics[?contains(TopicArn, `:skills-ceh-alert-topic`)].TopicArn' --output table
aws lambda get-function-configuration --region ap-southeast-1 --function-name skills-ceh-remediate-fn --query '{FunctionName:FunctionName,State:State,LastUpdateStatus:LastUpdateStatus,Runtime:Runtime,Handler:Handler,Timeout:Timeout,Role:Role,Environment:Environment.Variables}' --output table
```

### 판정 기준

```text
SNS Topic ARN에 skills-ceh-alert-topic이 포함되어야 합니다.
Lambda FunctionName=skills-ceh-remediate-fn, State=Active, Runtime=python3.12, Handler=remediate_security_group.lambda_handler, Timeout>=30이어야 합니다.
Environment에는 PROTECTED_SECURITY_GROUP_ID와 SNS_TOPIC_ARN이 존재해야 합니다.
```

## 채점 3-4

### 채점 명령어

```bash
aws cloudtrail get-trail-status --region ap-southeast-1 --name skills-ceh-cloudtrail --query '{IsLogging:IsLogging,LatestDeliveryTime:LatestDeliveryTime,LatestDeliveryError:LatestDeliveryError}' --output table
aws events describe-rule --region ap-southeast-1 --name skills-ceh-sg-change-rule --event-bus-name default --query '{Name:Name,State:State,EventPattern:EventPattern}' --output json
aws events list-targets-by-rule --region ap-southeast-1 --rule skills-ceh-sg-change-rule --event-bus-name default --query 'Targets[].{Id:Id,Arn:Arn}' --output table
aws lambda get-policy --region ap-southeast-1 --function-name skills-ceh-remediate-fn --query 'Policy' --output text
```

### 판정 기준

```text
CloudTrail IsLogging=True이어야 합니다.
EventBridge Rule Name=skills-ceh-sg-change-rule, State=ENABLED이어야 합니다.
EventPattern에 AuthorizeSecurityGroupIngress와 EC2 API Call via CloudTrail 조건이 포함되어야 합니다.
Target Arn은 skills-ceh-remediate-fn Lambda ARN이어야 합니다.
Lambda Policy에 events.amazonaws.com 호출 권한이 포함되어야 합니다.
```

## 채점 3-5

### 채점 명령어

```bash
export PROTECTED_SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --region ap-southeast-1 --filters Name=tag:Name,Values=skills-ceh-protected-sg --query 'SecurityGroups[0].GroupId' --output text)
aws ec2 authorize-security-group-ingress --region ap-southeast-1 --group-id "$PROTECTED_SECURITY_GROUP_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0
jq -n --arg sg "$PROTECTED_SECURITY_GROUP_ID" '{detail:{eventName:"AuthorizeSecurityGroupIngress",requestParameters:{groupId:$sg}}}' > /tmp/skills-ceh-remediate-event.json
aws lambda invoke --region ap-southeast-1 --function-name skills-ceh-remediate-fn --cli-binary-format raw-in-base64-out --payload file:///tmp/skills-ceh-remediate-event.json /tmp/skills-ceh-remediate-output.json
aws ec2 describe-security-groups --region ap-southeast-1 --group-ids "$PROTECTED_SECURITY_GROUP_ID" --query 'SecurityGroups[0].IpPermissions' --output json
aws logs describe-log-groups --region ap-southeast-1 --log-group-name-prefix /aws/lambda/skills-ceh-remediate-fn --query 'logGroups[].logGroupName' --output table
```

### 판정 기준

```text
Lambda Invoke가 성공해야 합니다.
180초 이내 SecurityGroups[0].IpPermissions가 빈 배열 []이어야 합니다.
/aws/lambda/skills-ceh-remediate-fn Log Group이 출력되어야 합니다.
본 항목은 CloudTrail 전달 지연 시간을 채점하지 않습니다.
```

## 모듈 4. EKS/SQS/KEDA/Karpenter

## 채점 4-1

### 채점 명령어

```bash
aws eks describe-cluster --region us-west-2 --name skills-sqs-cluster --query 'cluster.{Name:name,Status:status,Endpoint:endpoint,Version:version,Role:roleArn,Vpc:resourcesVpcConfig.vpcId,Subnets:resourcesVpcConfig.subnetIds}' --output table
aws eks describe-fargate-profile --region us-west-2 --cluster-name skills-sqs-cluster --fargate-profile-name skills-sqs-fp-keda --query 'fargateProfile.{Name:fargateProfileName,Status:status,Selectors:selectors,Subnets:subnets}' --output table
aws eks describe-fargate-profile --region us-west-2 --cluster-name skills-sqs-cluster --fargate-profile-name skills-sqs-fp-karpenter --query 'fargateProfile.{Name:fargateProfileName,Status:status,Selectors:selectors,Subnets:subnets}' --output table
aws eks update-kubeconfig --region us-west-2 --name skills-sqs-cluster
kubectl get nodes -l eks.amazonaws.com/compute-type=fargate -o wide
```

### 판정 기준

```text
Cluster Name=skills-sqs-cluster, Status=ACTIVE, Endpoint 출력, Vpc 및 Subnets 출력이 있어야 합니다.
Fargate Profile skills-sqs-fp-keda와 skills-sqs-fp-karpenter가 Status=ACTIVE이어야 합니다.
skills-sqs-fp-keda Selector namespace는 keda, skills-sqs-fp-karpenter Selector namespace는 karpenter이어야 합니다.
CloudShell에서 kubectl 접근이 가능하고 Fargate Node가 출력되어야 합니다.
```

## 채점 4-2

### 채점 명령어

```bash
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
```

### 판정 기준

```text
Queue URL이 출력되어야 합니다.
QueueArn이 출력되고 VisibilityTimeout>=30이어야 합니다.
keda/keda-operator, karpenter/karpenter, skills-sqs/sqs-worker-sa의 role-arn annotation이 비어 있지 않아야 합니다.
```

## 채점 4-3

### 채점 명령어

```bash
kubectl get deployment,pod -n keda -o wide
kubectl get deployment,pod -n karpenter -o wide
```

### 판정 기준

```text
keda-operator Deployment가 Available이고 Pod가 Running이어야 합니다.
karpenter Deployment가 Available이고 Pod가 Running이어야 합니다.
해당 Pod들은 Fargate Node에서 실행되어야 합니다.
```

## 채점 4-4

### 채점 명령어

```bash
kubectl get deployment sqs-worker -n skills-sqs -o jsonpath='name={.metadata.name}{"\n"}serviceAccountName={.spec.template.spec.serviceAccountName}{"\n"}selector={.spec.selector.matchLabels}{"\n"}podLabels={.spec.template.metadata.labels}{"\n"}nodeSelector={.spec.template.spec.nodeSelector}{"\n"}env={.spec.template.spec.containers[0].env}{"\n"}image={.spec.template.spec.containers[0].image}{"\n"}'
kubectl get scaledobject sqs-worker-scaledobject -n skills-sqs -o json | jq '{name:.metadata.name, namespace:.metadata.namespace, scaleTargetRef:.spec.scaleTargetRef, minReplicaCount:.spec.minReplicaCount, maxReplicaCount:.spec.maxReplicaCount, pollingInterval:.spec.pollingInterval, cooldownPeriod:.spec.cooldownPeriod, triggers:.spec.triggers}'
kubectl get triggerauthentication sqs-worker-trigger-auth -n skills-sqs -o json | jq '{name:.metadata.name, namespace:.metadata.namespace, podIdentity:.spec.podIdentity, secretTargetRef:.spec.secretTargetRef, env:.spec.env}'
```

### 판정 기준

```text
Deployment name=sqs-worker, serviceAccountName=sqs-worker-sa이어야 합니다.
selector/podLabels에 app=sqs-worker가 포함되어야 합니다.
nodeSelector에 karpenter.sh/nodepool=skills-sqs-nodepool, skills-nodepool=event-worker가 포함되어야 합니다.
env에 SQS_QUEUE_URL, AWS_REGION, PROCESSING_SECONDS가 있어야 합니다.
ScaledObject name=sqs-worker-scaledobject, scaleTargetRef.name=sqs-worker, minReplicaCount=0, maxReplicaCount=6, pollingInterval<=15, cooldownPeriod<=30이어야 합니다.
Trigger type은 aws-sqs-queue이고 queueLength=2이어야 합니다.
TriggerAuthentication name=sqs-worker-trigger-auth가 존재해야 합니다.
```

## 채점 4-5

### 채점 명령어

```bash
kubectl get nodepool skills-sqs-nodepool -o json | jq '{name:.metadata.name, labels:.spec.template.metadata.labels, nodeClassRef:.spec.template.spec.nodeClassRef, requirements:.spec.template.spec.requirements, consolidationPolicy:.spec.disruption.consolidationPolicy}'
kubectl get ec2nodeclass skills-sqs-nodeclass -o json | jq '{name:.metadata.name, role:.spec.role, instanceProfile:.spec.instanceProfile, subnetSelectorTerms:.spec.subnetSelectorTerms, securityGroupSelectorTerms:.spec.securityGroupSelectorTerms, amiFamily:.spec.amiFamily}'
kubectl get nodes -l karpenter.sh/nodepool=skills-sqs-nodepool,skills-nodepool=event-worker -o wide
kubectl get pods -n skills-sqs -l app=sqs-worker -o wide
```

### 판정 기준

```text
NodePool name=skills-sqs-nodepool이어야 합니다.
NodePool labels에 skills-nodepool=event-worker가 있어야 합니다.
NodePool nodeClassRef.name=skills-sqs-nodeclass이어야 합니다.
NodePool consolidationPolicy가 비어 있지 않아야 합니다.
EC2NodeClass name=skills-sqs-nodeclass이어야 하며 role 또는 instanceProfile이 출력되어야 합니다.
Karpenter EC2 Worker Node는 karpenter.sh/nodepool=skills-sqs-nodepool, skills-nodepool=event-worker Label을 가져야 합니다.
min 0으로 채점 직후 Worker Pod가 없을 수 있으므로 Worker Pod의 EC2 배치는 4-6 Scale Out 출력 결과를 포함해 판정할 수 있습니다.
```

## 채점 4-6

### 채점 명령어

```bash
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
```

### 판정 기준

```text
SQS 메시지 발행 수가 12개이어야 합니다.
마지막 메시지 발행 완료 후 180초 이내 sqs-worker Pod가 증가해야 합니다.
180초 이내 Karpenter EC2 Worker Node가 1개 이상 Ready 상태로 확인되어야 합니다.
SQS ApproximateNumberOfMessages가 감소해야 합니다.
ApproximateNumberOfMessagesNotVisible은 Worker가 처리 중인 메시지이므로, 대기 메시지가 감소하고 Pod가 처리 중이면 실패로 보지 않습니다.
Scale In 완료 시간은 채점하지 않습니다.
본 항목은 SQS 메시지를 생성하므로 4모듈의 마지막 채점 항목으로 수행합니다.
```

# 1~4모듈 채점 스크립트 수정안 (diff)

```diff
--- a/asgmt2_module1_check.sh
+++ b/asgmt2_module1_check.sh
@@ -5,13 +5,41 @@
 OUT_TXT="asgmt2_module1_check_result.txt"
 exec > >(tee "$OUT_TXT") 2>&1
 
-for CMD in aws jq curl; do
-  if ! command -v "$CMD" >/dev/null 2>&1; then
-    echo "ERROR: required command not found: $CMD" >&2
-    exit 2
+export PATH="$HOME/.local/bin:$PATH"
+
+install_base_tools() {
+  local packages=()
+  for CMD in "$@"; do
+    if ! command -v "$CMD" >/dev/null 2>&1; then
+      packages+=("$CMD")
+    fi
+  done
+  if [ "${#packages[@]}" -gt 0 ]; then
+    sudo dnf install -y "${packages[@]}"
   fi
-done
+}
 
+install_aws_cli() {
+  if command -v aws >/dev/null 2>&1; then
+    return 0
+  fi
+  local arch awscli_arch
+  arch=$(uname -m)
+  case "$arch" in
+    x86_64) awscli_arch="x86_64" ;;
+    aarch64|arm64) awscli_arch="aarch64" ;;
+    *) echo "지원하지 않는 CPU 아키텍처입니다: $arch" >&2; exit 2 ;;
+  esac
+  mkdir -p "$HOME/.local/bin"
+  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${awscli_arch}.zip" -o /tmp/awscliv2.zip
+  unzip -q -o /tmp/awscliv2.zip -d /tmp
+  /tmp/aws/install --install-dir "$HOME/usr/local/aws-cli" --bin-dir "$HOME/.local/bin" --update
+}
+
+install_base_tools curl jq unzip
+install_aws_cli
+
+
 echo "== 제2과제 1모듈 DocumentDB based NoSQL Application 채점 출력 =="
 echo
 
--- a/asgmt2_module2_check.sh
+++ b/asgmt2_module2_check.sh
@@ -5,13 +5,41 @@
 OUT_TXT="asgmt2_module2_check_result.txt"
 exec > >(tee "$OUT_TXT") 2>&1
 
-for CMD in aws curl; do
-  if ! command -v "$CMD" >/dev/null 2>&1; then
-    echo "ERROR: required command not found: $CMD" >&2
-    exit 2
+export PATH="$HOME/.local/bin:$PATH"
+
+install_base_tools() {
+  local packages=()
+  for CMD in "$@"; do
+    if ! command -v "$CMD" >/dev/null 2>&1; then
+      packages+=("$CMD")
+    fi
+  done
+  if [ "${#packages[@]}" -gt 0 ]; then
+    sudo dnf install -y "${packages[@]}"
   fi
-done
+}
 
+install_aws_cli() {
+  if command -v aws >/dev/null 2>&1; then
+    return 0
+  fi
+  local arch awscli_arch
+  arch=$(uname -m)
+  case "$arch" in
+    x86_64) awscli_arch="x86_64" ;;
+    aarch64|arm64) awscli_arch="aarch64" ;;
+    *) echo "지원하지 않는 CPU 아키텍처입니다: $arch" >&2; exit 2 ;;
+  esac
+  mkdir -p "$HOME/.local/bin"
+  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${awscli_arch}.zip" -o /tmp/awscliv2.zip
+  unzip -q -o /tmp/awscliv2.zip -d /tmp
+  /tmp/aws/install --install-dir "$HOME/usr/local/aws-cli" --bin-dir "$HOME/.local/bin" --update
+}
+
+install_base_tools curl unzip
+install_aws_cli
+
+
 echo "== 제2과제 2모듈 Simplify Service Networking with VPC Lattice 채점 출력 =="
 echo
 
--- a/asgmt2_module3_check.sh
+++ b/asgmt2_module3_check.sh
@@ -5,13 +5,41 @@
 OUT_TXT="asgmt2_module3_check_result.txt"
 exec > >(tee "$OUT_TXT") 2>&1
 
-for CMD in aws jq grep; do
-  if ! command -v "$CMD" >/dev/null 2>&1; then
-    echo "ERROR: required command not found: $CMD" >&2
-    exit 2
+export PATH="$HOME/.local/bin:$PATH"
+
+install_base_tools() {
+  local packages=()
+  for CMD in "$@"; do
+    if ! command -v "$CMD" >/dev/null 2>&1; then
+      packages+=("$CMD")
+    fi
+  done
+  if [ "${#packages[@]}" -gt 0 ]; then
+    sudo dnf install -y "${packages[@]}"
   fi
-done
+}
 
+install_aws_cli() {
+  if command -v aws >/dev/null 2>&1; then
+    return 0
+  fi
+  local arch awscli_arch
+  arch=$(uname -m)
+  case "$arch" in
+    x86_64) awscli_arch="x86_64" ;;
+    aarch64|arm64) awscli_arch="aarch64" ;;
+    *) echo "지원하지 않는 CPU 아키텍처입니다: $arch" >&2; exit 2 ;;
+  esac
+  mkdir -p "$HOME/.local/bin"
+  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${awscli_arch}.zip" -o /tmp/awscliv2.zip
+  unzip -q -o /tmp/awscliv2.zip -d /tmp
+  /tmp/aws/install --install-dir "$HOME/usr/local/aws-cli" --bin-dir "$HOME/.local/bin" --update
+}
+
+install_base_tools curl jq grep unzip
+install_aws_cli
+
+
 echo "== 제2과제 3모듈 Cloud Event Handling 채점 출력 =="
 echo
 
--- a/asgmt2_module4_check.sh
+++ b/asgmt2_module4_check.sh
@@ -5,25 +5,64 @@
 OUT_TXT="asgmt2_module4_check_result.txt"
 exec > >(tee "$OUT_TXT") 2>&1
 
-if ! command -v aws >/dev/null 2>&1; then
-  echo "ERROR: required command not found: aws" >&2
-  exit 2
-fi
-if ! command -v kubectl >/dev/null 2>&1; then
-  echo "ERROR: required command not found: kubectl" >&2
-  echo "CloudShell 또는 채점 환경에 kubectl을 준비한 뒤 다시 실행하십시오." >&2
-  exit 2
-fi
+export PATH="$HOME/.local/bin:$PATH"
 
+install_base_tools() {
+  local packages=()
+  for CMD in "$@"; do
+    if ! command -v "$CMD" >/dev/null 2>&1; then
+      packages+=("$CMD")
+    fi
+  done
+  if [ "${#packages[@]}" -gt 0 ]; then
+    sudo dnf install -y "${packages[@]}"
+  fi
+}
+
+install_aws_cli() {
+  if command -v aws >/dev/null 2>&1; then
+    return 0
+  fi
+  local arch awscli_arch
+  arch=$(uname -m)
+  case "$arch" in
+    x86_64) awscli_arch="x86_64" ;;
+    aarch64|arm64) awscli_arch="aarch64" ;;
+    *) echo "지원하지 않는 CPU 아키텍처입니다: $arch" >&2; exit 2 ;;
+  esac
+  mkdir -p "$HOME/.local/bin"
+  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${awscli_arch}.zip" -o /tmp/awscliv2.zip
+  unzip -q -o /tmp/awscliv2.zip -d /tmp
+  /tmp/aws/install --install-dir "$HOME/usr/local/aws-cli" --bin-dir "$HOME/.local/bin" --update
+}
+
+install_kubectl() {
+  if command -v kubectl >/dev/null 2>&1; then
+    return 0
+  fi
+  local arch kubectl_arch
+  arch=$(uname -m)
+  case "$arch" in
+    x86_64) kubectl_arch="amd64" ;;
+    aarch64|arm64) kubectl_arch="arm64" ;;
+    *) echo "지원하지 않는 CPU 아키텍처입니다: $arch" >&2; exit 2 ;;
+  esac
+  mkdir -p "$HOME/.local/bin"
+  curl -fsSL -o "$HOME/.local/bin/kubectl" "https://dl.k8s.io/release/v1.35.0/bin/linux/${kubectl_arch}/kubectl"
+  chmod +x "$HOME/.local/bin/kubectl"
+}
+
+install_base_tools curl jq unzip
+install_aws_cli
+install_kubectl
+
 echo "== 제2과제 4모듈 Event-driven Pod Scaling with AWS SQS 채점 출력 =="
 echo
 
 echo "[4-1] EKS Cluster, VPC, Fargate Profile 구성 (1.25점)"
-aws eks describe-cluster --region us-west-2 --name skills-sqs-cluster --query 'cluster.{Name:name,Status:status,Endpoint:endpoint,Version:version,Role:roleArn,Vpc:vpcConfig}' --output table
-for FP in skills-sqs-fp-keda skills-sqs-fp-karpenter; do
-  echo "fargate_profile=${FP}"
-  aws eks describe-fargate-profile --region us-west-2 --cluster-name skills-sqs-cluster --fargate-profile-name "$FP" --query 'fargateProfile.{Name:fargateProfileName,Status:status,Selectors:selectors,Subnets:subnets}' --output table
-done
+aws eks describe-cluster --region us-west-2 --name skills-sqs-cluster --query 'cluster.{Name:name,Status:status,Endpoint:endpoint,Version:version,Role:roleArn,Vpc:resourcesVpcConfig.vpcId,Subnets:resourcesVpcConfig.subnetIds}' --output table
+aws eks describe-fargate-profile --region us-west-2 --cluster-name skills-sqs-cluster --fargate-profile-name skills-sqs-fp-keda --query 'fargateProfile.{Name:fargateProfileName,Status:status,Selectors:selectors,Subnets:subnets}' --output table
+aws eks describe-fargate-profile --region us-west-2 --cluster-name skills-sqs-cluster --fargate-profile-name skills-sqs-fp-karpenter --query 'fargateProfile.{Name:fargateProfileName,Status:status,Selectors:selectors,Subnets:subnets}' --output table
 aws eks update-kubeconfig --region us-west-2 --name skills-sqs-cluster
 kubectl get nodes -l eks.amazonaws.com/compute-type=fargate -o wide
 
@@ -36,12 +75,9 @@
 else
   echo "skills-sqs-queue Queue URL 식별 실패"
 fi
-for X in "keda keda-operator" "karpenter karpenter" "skills-sqs sqs-worker-sa"; do
-  set -- $X
-  echo -n "$1/$2 role="
-  kubectl get serviceaccount "$2" -n "$1" -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'
-  echo
-done
+kubectl get serviceaccount keda-operator -n keda -o jsonpath='keda/keda-operator role={.metadata.annotations.eks\.amazonaws\.com/role-arn}{"\n"}'
+kubectl get serviceaccount karpenter -n karpenter -o jsonpath='karpenter/karpenter role={.metadata.annotations.eks\.amazonaws\.com/role-arn}{"\n"}'
+kubectl get serviceaccount sqs-worker-sa -n skills-sqs -o jsonpath='skills-sqs/sqs-worker-sa role={.metadata.annotations.eks\.amazonaws\.com/role-arn}{"\n"}'
 
 echo
 echo "[4-3] KEDA/Karpenter Controller Fargate 배포 구성 (1.25점)"
@@ -50,15 +86,14 @@
 
 echo
 echo "[4-4] Worker Application 및 KEDA ScaledObject 구성 (1.25점)"
-kubectl get deployment sqs-worker -n skills-sqs -o wide
-kubectl get deployment sqs-worker -n skills-sqs -o jsonpath='serviceAccountName={.spec.template.spec.serviceAccountName}{"\n"}selector={.spec.selector.matchLabels}{"\n"}podLabels={.spec.template.metadata.labels}{"\n"}nodeSelector={.spec.template.spec.nodeSelector}{"\n"}env={.spec.template.spec.containers[0].env}{"\n"}image={.spec.template.spec.containers[0].image}{"\n"}'
-kubectl get scaledobject sqs-worker-scaledobject -n skills-sqs -o yaml
-kubectl get triggerauthentication sqs-worker-trigger-auth -n skills-sqs -o yaml
+kubectl get deployment sqs-worker -n skills-sqs -o jsonpath='name={.metadata.name}{"\n"}serviceAccountName={.spec.template.spec.serviceAccountName}{"\n"}selector={.spec.selector.matchLabels}{"\n"}podLabels={.spec.template.metadata.labels}{"\n"}nodeSelector={.spec.template.spec.nodeSelector}{"\n"}env={.spec.template.spec.containers[0].env}{"\n"}image={.spec.template.spec.containers[0].image}{"\n"}'
+kubectl get scaledobject sqs-worker-scaledobject -n skills-sqs -o json | jq '{name:.metadata.name, namespace:.metadata.namespace, scaleTargetRef:.spec.scaleTargetRef, minReplicaCount:.spec.minReplicaCount, maxReplicaCount:.spec.maxReplicaCount, pollingInterval:.spec.pollingInterval, cooldownPeriod:.spec.cooldownPeriod, triggers:.spec.triggers}'
+kubectl get triggerauthentication sqs-worker-trigger-auth -n skills-sqs -o json | jq '{name:.metadata.name, namespace:.metadata.namespace, podIdentity:.spec.podIdentity, secretTargetRef:.spec.secretTargetRef, env:.spec.env}'
 
 echo
 echo "[4-5] Karpenter NodePool, EC2NodeClass 및 Worker EC2 배치 구성 (1.25점)"
-kubectl get nodepool skills-sqs-nodepool -o yaml
-kubectl get ec2nodeclass skills-sqs-nodeclass -o yaml
+kubectl get nodepool skills-sqs-nodepool -o json | jq '{name:.metadata.name, labels:.spec.template.metadata.labels, nodeClassRef:.spec.template.spec.nodeClassRef, requirements:.spec.template.spec.requirements, consolidationPolicy:.spec.disruption.consolidationPolicy}'
+kubectl get ec2nodeclass skills-sqs-nodeclass -o json | jq '{name:.metadata.name, role:.spec.role, instanceProfile:.spec.instanceProfile, subnetSelectorTerms:.spec.subnetSelectorTerms, securityGroupSelectorTerms:.spec.securityGroupSelectorTerms, amiFamily:.spec.amiFamily}'
 kubectl get nodes -l karpenter.sh/nodepool=skills-sqs-nodepool,skills-nodepool=event-worker -o wide
 kubectl get pods -n skills-sqs -l app=sqs-worker -o wide
 
@@ -69,9 +104,8 @@
   echo "skills-sqs-queue Queue URL 식별 실패"
 else
   SENT=0
-  RUN_ID="skills-scale-out-$(date +%s)"
   for I in $(seq 1 12); do
-    aws sqs send-message --region us-west-2 --queue-url "$QUEUE_URL" --message-body "${RUN_ID}-${I}" >/dev/null 2>&1 && SENT=$((SENT + 1))
+    aws sqs send-message --region us-west-2 --queue-url "$QUEUE_URL" --message-body "judge-$I" >/dev/null 2>&1 && SENT=$((SENT + 1))
   done
   echo "sent=${SENT}"
   for T in 60 120 180; do
```
