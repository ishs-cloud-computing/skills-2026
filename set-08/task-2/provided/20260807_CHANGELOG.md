# Summary

- Module 2
  - `CLIENT_IP`를 `LATTICE_CLIENT_EC2_PUBLIC_IP`로 명시
  - `VPC_ASSOCIATION_ID`를 채점지에서 명시되도록 수정
- Module 4
  - `4-1`에서 문제지에 명시되지 않은 `Version`, 채점 불필요한 `Role`을 제거 (버전은 풀이자가 직접 지정)
  - `4-1`에서 Fargate Profile 출력 부분을 `Namespaces` 중심으로 수정
  - `4-1`에서 Fargate Node 출력 부분을 필요한 값(이름)만 출력되도록 수정
  - `4-3`에서 `deployment,pod -o wide` 대신 JSON Path를 통해 최소한의 정보만 출력되도록 수정
  - `4-4`에서 `TriggerAuthentication` 출력에 대해 채점에 필요한 `name`, `namespace`, `podIdentity`만 남기도록 수정
  - `4-5`에서 Worker Node/Pod 출력을 JSON Path를 통해 최소한의 정보만 출력되도록 수정

# Changelog

## 채점 2-2

### 채점 명령어

```bash
aws ec2 describe-instances --region ap-northeast-1 --filters Name=tag:Name,Values=skills-lattice-client-ec2,skills-lattice-service-ec2 Name=instance-state-name,Values=running --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`].Value|[0],Id:InstanceId,Type:InstanceType,PublicIp:PublicIpAddress,PrivateIp:PrivateIpAddress,State:State.Name}' --output table
LATTICE_CLIENT_EC2_PUBLIC_IP=$(aws ec2 describe-instances --region ap-northeast-1 --filters Name=tag:Name,Values=skills-lattice-client-ec2 Name=instance-state-name,Values=running --query 'Reservations[0].Instances[0].PublicIpAddress' --output text 2>/dev/null || true)
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
SERVICE_NETWORK_ID=$(aws vpc-lattice list-service-networks --region ap-northeast-1 --query 'items[?name==`skills-lattice-sn`].id|[0]' --output text 2>/dev/null || true)
aws vpc-lattice list-service-networks --region ap-northeast-1 --query 'items[?name==`skills-lattice-sn`].{Name:name,Id:id,AssociatedVPCs:numberOfAssociatedVPCs,AssociatedServices:numberOfAssociatedServices}' --output table
aws vpc-lattice list-services --region ap-northeast-1 --query 'items[?name==`skills-lattice-order-service`].{Name:name,Id:id,Dns:dnsEntry.domainName,Status:status}' --output table
aws vpc-lattice list-service-network-vpc-associations --region ap-northeast-1 --service-network-identifier "$SERVICE_NETWORK_ID" --query 'items[].{AssociationId:id,VpcId:vpcId,Status:status}' --output table
VPC_ASSOCIATION_ID=$(aws vpc-lattice list-service-network-vpc-associations --region ap-northeast-1 --service-network-identifier "$SERVICE_NETWORK_ID" --query 'items[0].id' --output text 2>/dev/null || true)
echo "VPC_ASSOCIATION_ID=${VPC_ASSOCIATION_ID}"
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
TARGET_GROUP_ID=$(aws vpc-lattice list-target-groups --region ap-northeast-1 --query 'items[?name==`skills-lattice-order-tg`].id|[0]' --output text 2>/dev/null || true)
SERVICE_ID=$(aws vpc-lattice list-services --region ap-northeast-1 --query 'items[?name==`skills-lattice-order-service`].id|[0]' --output text 2>/dev/null || true)
SERVICE_SG_IDS=$(aws ec2 describe-instances --region ap-northeast-1 --filters Name=tag:Name,Values=skills-lattice-service-ec2 Name=instance-state-name,Values=running --query 'Reservations[0].Instances[0].SecurityGroups[].GroupId' --output text 2>/dev/null || true)
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
LATTICE_CLIENT_EC2_PUBLIC_IP=$(aws ec2 describe-instances --region ap-northeast-1 --filters Name=tag:Name,Values=skills-lattice-client-ec2 Name=instance-state-name,Values=running --query 'Reservations[0].Instances[0].PublicIpAddress' --output text 2>/dev/null || true)
curl -s -m 10 -w "\nhttp_code=%{http_code}\n" "http://${LATTICE_CLIENT_EC2_PUBLIC_IP}/v1/client/orders?id=1001"
```

### 판정 기준

```text
http_code=200이어야 합니다.
응답 JSON에 client=ok, service.order_id=1001, service.via=vpc-lattice가 포함되어야 합니다.
```

## 채점 4-1

### 채점 명령어

```bash
aws eks describe-cluster --region us-west-2 --name skills-sqs-cluster --query 'cluster.{Name:name,Status:status,Endpoint:endpoint,VpcId:resourcesVpcConfig.vpcId,Subnets:resourcesVpcConfig.subnetIds}' --output table
aws eks describe-fargate-profile --region us-west-2 --cluster-name skills-sqs-cluster --fargate-profile-name skills-sqs-fp-keda --query 'fargateProfile.{Name:fargateProfileName,Status:status,Namespaces:selectors[].namespace}' --output table
aws eks describe-fargate-profile --region us-west-2 --cluster-name skills-sqs-cluster --fargate-profile-name skills-sqs-fp-karpenter --query 'fargateProfile.{Name:fargateProfileName,Status:status,Namespaces:selectors[].namespace}' --output table
aws eks update-kubeconfig --region us-west-2 --name skills-sqs-cluster
kubectl get nodes -l eks.amazonaws.com/compute-type=fargate -o json | jq '[.items[] | {name:.metadata.name}]'
```

### 판정 기준

```text
Cluster Name=skills-sqs-cluster, Status=ACTIVE, Endpoint 출력, VpcId 및 Subnets 출력이 있어야 합니다.
Fargate Profile skills-sqs-fp-keda와 skills-sqs-fp-karpenter가 Status=ACTIVE이어야 합니다.
skills-sqs-fp-keda Namespaces에 keda, skills-sqs-fp-karpenter Namespaces에 karpenter가 포함되어야 합니다.
CloudShell에서 kubectl 접근이 가능하고 Fargate Node 이름이 출력되어야 합니다.
```

## 채점 4-3

### 채점 명령어

```bash
kubectl get deployment keda-operator -n keda -o json | jq '{name:.metadata.name, availableReplicas:(.status.availableReplicas // 0), readyReplicas:(.status.readyReplicas // 0)}'
kubectl get pods -n keda -o json | jq '[.items[] | select(.metadata.name | test("^keda-operator-")) | {name:.metadata.name, phase:.status.phase, node:.spec.nodeName}]'
kubectl get deployment karpenter -n karpenter -o json | jq '{name:.metadata.name, availableReplicas:(.status.availableReplicas // 0), readyReplicas:(.status.readyReplicas // 0)}'
kubectl get pods -n karpenter -o json | jq '[.items[] | select(.metadata.name | test("^karpenter-")) | {name:.metadata.name, phase:.status.phase, node:.spec.nodeName}]'
```

### 판정 기준

```text
keda-operator Deployment의 availableReplicas가 1 이상이어야 합니다.
karpenter Deployment의 availableReplicas가 1 이상이어야 합니다.
각 Deployment Pod의 phase는 Running이어야 합니다.
해당 Pod들은 Fargate Node에서 실행되어야 합니다.
```

## 채점 4-4

### 채점 명령어

```bash
kubectl get deployment sqs-worker -n skills-sqs -o jsonpath='name={.metadata.name}{"\n"}serviceAccountName={.spec.template.spec.serviceAccountName}{"\n"}selector={.spec.selector.matchLabels}{"\n"}podLabels={.spec.template.metadata.labels}{"\n"}nodeSelector={.spec.template.spec.nodeSelector}{"\n"}env={.spec.template.spec.containers[0].env}{"\n"}image={.spec.template.spec.containers[0].image}{"\n"}'
kubectl get scaledobject sqs-worker-scaledobject -n skills-sqs -o json | jq '{name:.metadata.name, namespace:.metadata.namespace, scaleTargetRef:.spec.scaleTargetRef, minReplicaCount:.spec.minReplicaCount, maxReplicaCount:.spec.maxReplicaCount, pollingInterval:.spec.pollingInterval, cooldownPeriod:.spec.cooldownPeriod, triggers:.spec.triggers}'
kubectl get triggerauthentication sqs-worker-trigger-auth -n skills-sqs -o json | jq '{name:.metadata.name, namespace:.metadata.namespace, podIdentity:.spec.podIdentity}'
```

### 판정 기준

```text
Deployment name=sqs-worker, serviceAccountName=sqs-worker-sa이어야 합니다.
selector/podLabels에 app=sqs-worker가 포함되어야 합니다.
nodeSelector에 karpenter.sh/nodepool=skills-sqs-nodepool, skills-nodepool=event-worker가 포함되어야 합니다.
env에 SQS_QUEUE_URL, AWS_REGION, PROCESSING_SECONDS가 있어야 합니다.
ScaledObject name=sqs-worker-scaledobject, scaleTargetRef.name=sqs-worker, minReplicaCount=0, maxReplicaCount=6, pollingInterval<=15, cooldownPeriod<=30이어야 합니다.
Trigger type은 aws-sqs-queue이고 queueLength=2이어야 합니다.
TriggerAuthentication name=sqs-worker-trigger-auth, namespace=skills-sqs가 출력되어야 합니다.
podIdentity.provider=aws-eks이어야 합니다.
```
