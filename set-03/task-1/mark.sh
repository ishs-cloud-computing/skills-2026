#!/bin/bash

aws configure set default.region ap-northeast-2
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=wsc2026-skills-vpc" --query "Vpcs[0].VpcId" --output text)
BUCKET=$(aws s3api list-buckets --query "Buckets[?contains(Name,'wsc2026-static')].Name" --output text)
aws eks update-kubeconfig --name wsc2026-eks-cluster --region ap-northeast-2 2>/dev/null
check_kms() {
  local ALIAS=$1 ACTUAL_ARN=$2; local EXPECTED_ARN=$(aws kms describe-key --key-id "alias/${ALIAS}" --query "KeyMetadata.Arn" --output text 2>/dev/null); local KEY_ID=$(aws kms describe-key --key-id "alias/${ALIAS}" --query "KeyMetadata.KeyId" --output text 2>/dev/null)
  if [ -z "$KEY_ID" ] || [ "$KEY_ID" = "None" ]; then echo "KMS ${ALIAS}: FAIL (key not found)"; return; fi
  if [ "$EXPECTED_ARN" != "$ACTUAL_ARN" ]; then echo "KMS ${ALIAS}: FAIL (wrong key)"; return; fi
  POLICY=$(aws kms get-key-policy --key-id "$KEY_ID" --policy-name default --output text 2>/dev/null)
  if echo "$POLICY" | grep -q '"kms:\*"'; then echo "KMS ${ALIAS}: FAIL (kms:*)"; elif echo "$POLICY" | grep -q ':root"'; then echo "KMS ${ALIAS}: FAIL (root)"; else echo "KMS ${ALIAS}: PASS"; fi
}

# ── 정본과 의도적으로 다른 지점 ────────────────────────────────────────────────
# 최종 채점지는 부하 파드 6종 생성 + `sleep 180` 을 11-1 과 11-3 **양쪽에** 둔다.
# 11-3 실행분은 AlreadyExists 로 조용히 실패하고 sleep 만 다시 돌아, 리허설마다 6분이 나간다.
# 그 6분은 검증이 아니라 알람 룰의 `for: 3m`(prometheus-rules.yaml:26,37,50,82)을 채우는 고정 대기일 뿐이고,
# 11-1 의 실제 검사(observability 파드 Running 수)는 부하 파드와 무관하다.
# 그래서 이 스크립트는 ① 파드 생성을 5-5 직후 1회로 옮기고(6-1~10-1 도는 동안 3분 시계가 흐른다)
#                    ② `sleep 180` 대신 ALERTS{alertstate="firing"} 를 폴링해 뜨는 즉시 통과한다.
# 결과: 대기가 사실상 0 에 수렴하고, "어떤 알람이 떴는지"라는 실질 검증이 생긴다.
# 파드 생성을 맨 앞이 아니라 5절 뒤에 두는 이유: 5-4 가 wsc2026 네임스페이스 파드를 나열하므로
# 앞에서 띄우면 채점자가 볼 5-4 출력과 달라진다(합격 조건은 book-deploy 필터라 PASS/FAIL 은 불변).
# ──────────────────────────────────────────────────────────────────────────────

GRAFANA_CRED='admin:Skills$#$@!'

start_load_pods() {
  local SVC_IP
  SVC_IP=$(kubectl get svc -n wsc2026 -o jsonpath='{.items[0].spec.clusterIP}' 2>/dev/null)
  kubectl run not-ready --image=busybox --restart=Always -n wsc2026 --overrides='{"spec":{"tolerations":[{"operator":"Exists"}],"nodeSelector":{"wsc2026/node":"application"},"containers":[{"name":"not-ready","image":"busybox","readinessProbe":{"httpGet":{"path":"/health","port":80},"periodSeconds":3},"command":["sh","-c","sleep 3600"]}]}}' &>/dev/null
  kubectl run error-gen --image=curlimages/curl --restart=Never -n wsc2026 --overrides='{"spec":{"tolerations":[{"operator":"Exists"}],"nodeSelector":{"wsc2026/node":"application"}}}' -- sh -c "while true; do curl -s -o /dev/null http://${SVC_IP}/nonexist; sleep 0.1; done" &>/dev/null
  kubectl run latency-gen --image=curlimages/curl --restart=Never -n wsc2026 --overrides='{"spec":{"tolerations":[{"operator":"Exists"}],"nodeSelector":{"wsc2026/node":"application"}}}' -- sh -c "while true; do curl -s -o /dev/null http://${SVC_IP}/delay?ms=5000; sleep 0.2; done" &>/dev/null
  kubectl run crash-test --image=busybox --restart=Always -n wsc2026 --overrides='{"spec":{"tolerations":[{"operator":"Exists"}],"nodeSelector":{"wsc2026/node":"application"}}}' -- sh -c 'exit 1' &>/dev/null
  kubectl run stress-cpu --image=busybox --restart=Never -n wsc2026 --overrides='{"spec":{"tolerations":[{"operator":"Exists"}],"nodeSelector":{"wsc2026/node":"application"},"containers":[{"name":"stress-cpu","image":"busybox","resources":{"requests":{"cpu":"250m"},"limits":{"cpu":"250m"}},"command":["sh","-c","while true; do :; done"]}]}}' &>/dev/null
  kubectl run stress-mem --image=polinux/stress --restart=Never -n wsc2026 --overrides='{"spec":{"tolerations":[{"operator":"Exists"}],"nodeSelector":{"wsc2026/node":"application"},"containers":[{"name":"stress-mem","image":"polinux/stress","resources":{"requests":{"memory":"64Mi"},"limits":{"memory":"64Mi"}},"command":["stress","--vm","1","--vm-bytes","60M","--vm-keep","-t","3600"]}]}}' &>/dev/null
}

# 기대 알람 5종이 Firing 될 때까지 폴링. 정본의 `sleep 180` 을 대체한다(백스톱 4분).
wait_for_alerts() {
  local EXPECTED="PodHighCPU PodHighMemory PodNotReady HighErrorRate PodCrashLooping"
  local DEADLINE=$(( $(date +%s) + 240 ))
  local PROM_UID FIRING MISSING a
  PROM_UID=$(curl -s -u "$GRAFANA_CRED" "http://${GRAFANA_LB}/api/datasources" 2>/dev/null     | python3 -c "import sys,json;print(next((d['uid'] for d in json.load(sys.stdin) if d['type']=='prometheus'),''))" 2>/dev/null)
  if [ -z "$PROM_UID" ]; then echo "  prometheus datasource 조회 실패 — Grafana 에서 수동 확인"; return 1; fi
  while :; do
    FIRING=$(curl -s -u "$GRAFANA_CRED" --get --data-urlencode 'query=ALERTS{alertstate="firing"}'       "http://${GRAFANA_LB}/api/datasources/proxy/uid/${PROM_UID}/api/v1/query" 2>/dev/null       | python3 -c "import sys,json;print(' '.join(sorted({r['metric'].get('alertname','') for r in json.load(sys.stdin)['data']['result']})))" 2>/dev/null)
    MISSING=""
    for a in $EXPECTED; do echo " $FIRING " | grep -q " $a " || MISSING="$MISSING $a"; done
    echo "  firing:[${FIRING}] 미발화:[${MISSING:- 없음}]"
    [ -z "$MISSING" ] && { echo "  -> 기대 알람 5종 전부 Firing"; return 0; }
    [ "$(date +%s)" -ge "$DEADLINE" ] && { echo "  -> 타임아웃(4분). 미발화:$MISSING"; return 1; }
    sleep 15
  done
}

echo =====1-1=====
aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --query "Vpcs[0].CidrBlock" --output text; aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" --query "Subnets[].{Name:Tags[?Key=='Name'].Value|[0],CIDR:CidrBlock}" --output text
echo 

echo =====1-2=====
IGW_ID=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=wsc2026-skills-igw" --query "InternetGateways[0].InternetGatewayId" --output text); echo "IGW: $IGW_ID"
NAT_A_ID=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=wsc2026-skills-nat-a" "Name=state,Values=available" --query "NatGateways[0].NatGatewayId" --output text); NAT_B_ID=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=wsc2026-skills-nat-b" "Name=state,Values=available" --query "NatGateways[0].NatGatewayId" --output text); echo "NAT-A: $NAT_A_ID"; echo "NAT-B: $NAT_B_ID"
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=*" --query "RouteTables[].{Name:Tags[?Key=='Name'].Value|[0],Route:Routes[?DestinationCidrBlock=='0.0.0.0/0']|[0]}" --output text
echo

echo =====2-1=====
aws dynamodb describe-table --table-name wsc2026-book-table --query "Table.[KeySchema[0].AttributeName,BillingModeSummary.BillingMode,SSEDescription.SSEType,DeletionProtectionEnabled,GlobalSecondaryIndexes[0].KeySchema[0].AttributeName]" --output text 2>/dev/null
aws dynamodb describe-continuous-backups --table-name wsc2026-book-table --query "ContinuousBackupsDescription.[PointInTimeRecoveryDescription.PointInTimeRecoveryStatus,PointInTimeRecoveryDescription.RecoveryPeriodInDays,ContinuousBackupsStatus]" --output text 2>/dev/null
aws dynamodb get-resource-policy --resource-arn "arn:aws:dynamodb:ap-northeast-2:${ACCOUNT_ID}:table/wsc2026-book-table" --query "Policy" --output text 2>/dev/null | python3 -c "import sys,json;[print(f'  {s.get(\"Action\",\"\")} : {s.get(\"Principal\",{}).get(\"AWS\",\"\").split(\"/\")[-1]}') for s in json.loads(sys.stdin.read()).get('Statement',[])]" 2>/dev/null || echo "No resource policy"
check_kms "wsc2026-db-kms" "$(aws dynamodb describe-table --table-name wsc2026-book-table --query 'Table.SSEDescription.KMSMasterKeyArn' --output text 2>/dev/null)"
echo

echo =====3-1=====
aws ecr describe-repositories --repository-names wsc2026-book-ecr --query "repositories[0].[imageScanningConfiguration.scanOnPush,imageTagMutability,imageTagMutabilityExclusionFilters[0].filter,encryptionConfiguration.encryptionType]" --output text 2>/dev/null; aws ecr list-images --repository-name wsc2026-book-ecr --query "imageIds[].imageTag" --output text 2>/dev/null
check_kms "wsc2026-ecr-kms" "$(aws ecr describe-repositories --repository-names wsc2026-book-ecr --query 'repositories[0].encryptionConfiguration.kmsKey' --output text 2>/dev/null)"
echo

echo =====4-1=====
aws eks describe-cluster --name wsc2026-eks-cluster --query "cluster.[version,status,resourcesVpcConfig.endpointPublicAccess,resourcesVpcConfig.endpointPrivateAccess,logging.clusterLogging[0].enabled]" --output text 2>/dev/null
CLUSTER_SG=$(aws eks describe-cluster --name wsc2026-eks-cluster --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" --output text 2>/dev/null); ANYIP=$(aws ec2 describe-security-groups --group-ids "$CLUSTER_SG" --query "SecurityGroups[0].IpPermissions[?IpProtocol=='-1'].IpRanges[].CidrIp" --output text 2>/dev/null); if [ -n "$ANYIP" ]; then echo "SG: FAIL"; else echo "SG: PASS"; fi
kubectl get configmap coredns -n kube-system -o jsonpath='{.data.Corefile}' 2>/dev/null | grep -oP 'kubernetes \K[^ ]+'
check_kms "wsc2026-eks-kms" "$(aws eks describe-cluster --name wsc2026-eks-cluster --query 'cluster.encryptionConfig[0].provider.keyArn' --output text 2>/dev/null)"
echo

echo =====4-2=====
NG1=$(aws eks describe-nodegroup --cluster-name wsc2026-eks-cluster --nodegroup-name wsc2026-addon-nodegroup --query "nodegroup.[nodegroupName,instanceTypes[0]]" --output text 2>/dev/null); echo "$NG1	wsc2026/node=addon"
ADDON_COUNT=$(kubectl get nodes -l wsc2026/node=addon --no-headers --request-timeout=10s 2>/dev/null | wc -l)
if [ "$ADDON_COUNT" -ge 1 ]; then echo "Addon Nodes: PASS ($ADDON_COUNT)"; else echo "Addon Nodes: FAIL"; fi
NG2=$(aws eks describe-nodegroup --cluster-name wsc2026-eks-cluster --nodegroup-name wsc2026-workload-ng --query "nodegroup.[nodegroupName,instanceTypes[0]]" --output text 2>/dev/null); echo "$NG2	wsc2026/node=application"
WORK_COUNT=$(kubectl get nodes -l wsc2026/node=application --no-headers --request-timeout=10s 2>/dev/null | wc -l)
if [ "$WORK_COUNT" -ge 1 ]; then echo "Workload Nodes: PASS ($WORK_COUNT)"; else echo "Workload Nodes: FAIL"; fi
echo

echo =====4-3=====
CR=$(aws eks describe-cluster --name wsc2026-eks-cluster --query "cluster.roleArn" --output text 2>/dev/null | awk -F/ '{print $NF}'); AR=$(aws eks describe-nodegroup --cluster-name wsc2026-eks-cluster --nodegroup-name wsc2026-addon-nodegroup --query "nodegroup.nodeRole" --output text 2>/dev/null | awk -F/ '{print $NF}'); WR=$(aws eks describe-nodegroup --cluster-name wsc2026-eks-cluster --nodegroup-name wsc2026-workload-ng --query "nodegroup.nodeRole" --output text 2>/dev/null | awk -F/ '{print $NF}')
for PAIR in "Cluster Role:$CR" "Addon Node Role:$AR" "Workload Node Role:$WR"; do LABEL="${PAIR%%:*}"; ROLE="${PAIR#*:}"; ADMIN=$(aws iam list-attached-role-policies --role-name "$ROLE" --query "AttachedPolicies[?PolicyName=='AdministratorAccess'].PolicyName" --output text 2>/dev/null); if [ -n "$ADMIN" ]; then echo "$LABEL: FAIL"; else echo "$LABEL: PASS"; fi; done
echo

echo =====5-1=====
kubectl get deploy,svc,ingress,pdb -n wsc2026 --no-headers 2>/dev/null | awk '
/^deployment/ { split($2,a,"/"); print "Deployment: " (a[1]==a[2] && a[1]=="2" ? "PASS" : "FAIL") }
/^service/    { print "Service: PASS" }
/^ingress/    { print "Ingress: " ($4 ~ /\.elb\.amazonaws\.com/ ? "PASS ("$4")" : "FAIL") }
/^poddisrupt/ { print "PDB: " ($2=="1" ? "PASS" : "FAIL") }
'
echo

echo =====5-2=====
kubectl get deploy wsc2026-book-deploy -n wsc2026 -o jsonpath='replicas:{.spec.replicas} node:{.spec.template.spec.nodeSelector.wsc2026/node} topo:{.spec.template.spec.topologySpreadConstraints[0].topologyKey} cpu:{.spec.template.spec.containers[0].resources.requests.cpu} mem:{.spec.template.spec.containers[0].resources.requests.memory}' 2>/dev/null; echo
echo

echo =====5-3=====
kubectl get deploy wsc2026-book-deploy -n wsc2026 -o jsonpath='startup:{.spec.template.spec.containers[0].startupProbe.httpGet.path}:{.spec.template.spec.containers[0].startupProbe.httpGet.port} readiness:{.spec.template.spec.containers[0].readinessProbe.httpGet.path}:{.spec.template.spec.containers[0].readinessProbe.httpGet.port} liveness:{.spec.template.spec.containers[0].livenessProbe.httpGet.path}:{.spec.template.spec.containers[0].livenessProbe.httpGet.port}' 2>/dev/null; echo; kubectl get configmap book-config -n wsc2026 -o jsonpath='{.data}' 2>/dev/null; echo
echo

echo =====5-4=====
WORKLOAD_NODES=$(kubectl get nodes -l wsc2026/node=application --no-headers -o custom-columns='NAME:.metadata.name' 2>/dev/null)
kubectl get pods -n wsc2026 -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName' --no-headers 2>/dev/null | while read NAME STATUS NODE; do
  echo "$NAME: $(echo "$WORKLOAD_NODES" | grep -q "^$NODE$" && echo PASS || echo FAIL)"
done
echo

echo =====5-5=====
PI_SA=$(aws eks list-pod-identity-associations --cluster-name wsc2026-eks-cluster --namespace wsc2026 --query 'associations[0].serviceAccount' --output text 2>/dev/null)
PI_ROLE=$(aws eks list-pod-identity-associations --cluster-name wsc2026-eks-cluster --namespace wsc2026 --query 'associations[0].associationId' --output text 2>/dev/null)
[ "$PI_SA" = "wsc2026-book-sa" ] && echo "Pod Identity SA: PASS ($PI_SA)" || echo "Pod Identity SA: FAIL ($PI_SA)"
ROLE_NAME=$(aws eks describe-pod-identity-association --cluster-name wsc2026-eks-cluster --association-id "$PI_ROLE" --query 'association.roleArn' --output text 2>/dev/null|awk -F/ '{print $NF}')
MANAGED_ACTIONS=$(aws iam list-attached-role-policies --role-name "$ROLE_NAME" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null|tr '\t' '\n'|while read arn;do VERSION=$(aws iam get-policy --policy-arn "$arn" --query 'Policy.DefaultVersionId' --output text 2>/dev/null);aws iam get-policy-version --policy-arn "$arn" --version-id "$VERSION" --query 'PolicyVersion.Document.Statement[].Action' --output text 2>/dev/null;done)
echo "$MANAGED_ACTIONS"|grep -q dynamodb:PutItem && ! echo "$MANAGED_ACTIONS"|grep -qE '^\*$' && echo "Pod Identity Role: PASS" || echo "Pod Identity Role: FAIL"
echo

# 정본은 이 파드들을 11-1 에서 만든다. 여기서 미리 띄워 6-1~10-1 도는 동안 알람 `for: 3m` 이 흐르게 한다.
echo "----- 부하/장애 파드 생성 (정본 11-1 상당, 조기 실행) -----"
start_load_pods
echo

echo =====6-1=====
echo "$BUCKET"; aws s3api get-public-access-block --bucket "$BUCKET" --query "PublicAccessBlockConfiguration.[BlockPublicAcls,BlockPublicPolicy,IgnorePublicAcls,RestrictPublicBuckets]" --output text 2>/dev/null; aws s3api get-bucket-encryption --bucket "$BUCKET" --query "ServerSideEncryptionConfiguration.Rules[0].{SSE:ApplyServerSideEncryptionByDefault.SSEAlgorithm,BucketKey:BucketKeyEnabled}" --output text 2>/dev/null; aws s3api list-objects --bucket "$BUCKET" --prefix "static/" --query "Contents[?Size>\`0\`].Key" --output text 2>/dev/null
check_kms "wsc2026-bucket-kms" "$(aws s3api get-bucket-encryption --bucket "$BUCKET" --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.KMSMasterKeyID' --output text 2>/dev/null)"
BUCKET_KMS_ARN=$(aws kms describe-key --key-id "alias/wsc2026-bucket-kms" --query "KeyMetadata.Arn" --output text 2>/dev/null)
echo "S3 Object KMS Check:"; for OBJ in $(aws s3api list-objects --bucket "$BUCKET" --prefix "static/" --query "Contents[].Key" --output text 2>/dev/null); do
  KEY_ID=$(aws s3api head-object --bucket "$BUCKET" --key "$OBJ" --query "SSEKMSKeyId" --output text 2>/dev/null)
  if [ "$KEY_ID" = "$BUCKET_KMS_ARN" ]; then echo "  $OBJ: PASS"; else echo "  $OBJ: FAIL ($KEY_ID)"; fi
done
echo

echo =====7-1=====
aws lambda get-function --function-name wsc2026-book-get-function --query "Configuration.{Name:FunctionName,Runtime:Runtime}" --output json 2>/dev/null
aws lambda get-function --function-name wsc2026-book-get-function --query "Configuration.Environment.Variables" --output json 2>/dev/null
check_kms "wsc2026-function-kms" "$(aws lambda get-function --function-name wsc2026-book-get-function --query 'Configuration.KMSKeyArn' --output text 2>/dev/null)"
echo

echo =====7-2=====
LAMBDA_ROLE=$(aws lambda get-function --function-name wsc2026-book-get-function --query "Configuration.Role" --output text 2>/dev/null | awk -F/ '{print $NF}'); echo "$LAMBDA_ROLE"; POLICIES=$(aws iam list-attached-role-policies --role-name "$LAMBDA_ROLE" --query "AttachedPolicies[].PolicyName" --output text 2>/dev/null); echo "$POLICIES"; if echo "$POLICIES" | grep -q "AdministratorAccess"; then echo "Role: FAIL (Admin)"; else echo "Role: PASS"; fi
POLICY_ARN=$(aws iam list-attached-role-policies --role-name "$LAMBDA_ROLE" --query "AttachedPolicies[?PolicyName!='AWSLambdaBasicExecutionRole'].PolicyArn|[0]" --output text 2>/dev/null); ACTIONS=$(aws iam get-policy-version --policy-arn "$POLICY_ARN" --version-id $(aws iam get-policy --policy-arn "$POLICY_ARN" --query "Policy.DefaultVersionId" --output text 2>/dev/null) --query "PolicyVersion.Document.Statement[].Action" --output text 2>/dev/null)
if echo "$ACTIONS" | grep -q "dynamodb:Query" && ! echo "$ACTIONS" | grep -q '\*'; then echo "Policy: PASS"; else echo "Policy: FAIL"; fi
echo

echo =====8-1=====
aws elbv2 describe-load-balancers --names wsc2026-app-alb --query "LoadBalancers[0].Scheme" --output text 2>/dev/null; ALB_SGS=$(aws elbv2 describe-load-balancers --names wsc2026-app-alb --query "LoadBalancers[0].SecurityGroups[]" --output text 2>/dev/null); aws ec2 describe-security-groups --group-ids $ALB_SGS --query "SecurityGroups[].GroupName" --output text 2>/dev/null
ALB_DNS=$(aws elbv2 describe-load-balancers --names wsc2026-app-alb --query "LoadBalancers[0].DNSName" --output text 2>/dev/null); ALB_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://${ALB_DNS}/" 2>/dev/null); if [ "$ALB_CODE" = "000" ]; then echo "ALB direct: BLOCKED"; else echo "ALB direct: FAIL ($ALB_CODE)"; fi
echo

echo =====9-1=====
CF_ARN=$(aws resourcegroupstaggingapi get-resources --tag-filters Key=Name,Values=wsc2026-cdn --resource-type-filters cloudfront --region us-east-1 --query "ResourceTagMappingList[0].ResourceARN" --output text 2>/dev/null); CF_ID=$(echo "$CF_ARN" | awk -F/ '{print $NF}'); CF_DOMAIN=$(aws cloudfront get-distribution --id "$CF_ID" --region us-east-1 --query "Distribution.DomainName" --output text 2>/dev/null); curl -s -o /dev/null -w "${CF_DOMAIN} : %{http_code}" "https://${CF_DOMAIN}/" 2>/dev/null; echo
echo

echo =====9-2=====
DISABLED="4135ea2d-6df8-44a3-9df3-4b5a84be39ad"; OPTIMIZED="658327ea-f89d-4fab-a63d-7e88639e58f6"; DEFAULT_CP=$(aws cloudfront get-distribution --id "$CF_ID" --region us-east-1 --query "Distribution.DistributionConfig.DefaultCacheBehavior.CachePolicyId" --output text 2>/dev/null); if [ "$DEFAULT_CP" = "$OPTIMIZED" ]; then echo "S3: CachingOptimized"; else echo "S3: FAIL"; fi
for B in $(aws cloudfront get-distribution --id "$CF_ID" --region us-east-1 --query "Distribution.DistributionConfig.CacheBehaviors.Items[].PathPattern" --output text 2>/dev/null); do CP=$(aws cloudfront get-distribution --id "$CF_ID" --region us-east-1 --query "Distribution.DistributionConfig.CacheBehaviors.Items[?PathPattern=='${B}'].CachePolicyId|[0]" --output text 2>/dev/null); if [ "$CP" = "$DISABLED" ]; then echo "ALB/Lambda: CachingDisabled"; break; fi; done
echo

echo =====9-3=====
# 정정 2026-08-16: created_at 은 curl 요청 직전 시스템 시간(date) 기준 1분 이내로 판정한다
TZ=Asia/Seoul date '+REQUEST TIME: %Y-%m-%d %H:%M:%S KST'
BOOKING_ID=$(curl -s -X POST "https://${CF_DOMAIN}/booking" -H "Content-Type: application/json" -d '{"client_id":"MARK001","username":"Marker","email":"mark@test.com","concert_name":"TestConcert"}' 2>/dev/null | python3 -c "import sys,json;print(json.load(sys.stdin).get('booking_id',''))" 2>/dev/null); echo "POST booking_id: $BOOKING_ID"
curl -s "https://${CF_DOMAIN}/v1/book?booking_id=${BOOKING_ID}" 2>/dev/null; echo
echo

echo =====10-1=====
WAF_NAME=$(aws wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1 --query "WebACLs[?contains(Name, 'wsc2026')].Name" --output text 2>/dev/null)
echo "WAF Name: $WAF_NAME"
SQLI=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "https://${CF_DOMAIN}/v1/book?booking_id=1'%20OR%201=1--"); echo "SQLi: $SQLI"
XSS=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "https://${CF_DOMAIN}/v1/book?booking_id=<script>alert(1)</script>"); echo "XSS: $XSS"
(for i in $(seq 1 15); do for j in $(seq 1 25); do curl -s -o /dev/null --max-time 3 "https://${CF_DOMAIN}/" & done; sleep 0.4; done; wait) >/dev/null 2>&1; WAF_ID=$(aws wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1 --query "WebACLs[?contains(Name, 'wsc2026')].Id" --output text 2>/dev/null); RATE_LIMIT=$(aws wafv2 get-web-acl --scope CLOUDFRONT --region us-east-1 --name "$WAF_NAME" --id "$WAF_ID" --query "WebACL.Rules[?Statement.RateBasedStatement].Statement.RateBasedStatement.Limit" --output text 2>/dev/null); if [ -n "$RATE_LIMIT" ] && [ "$RATE_LIMIT" -le 200 ] 2>/dev/null; then echo "Rate: PASS (403)"; else echo "Rate: FAIL (-)"; fi
echo

echo =====11-1=====
# 부하 파드는 5-5 직후에 이미 생성했다(정본은 여기서 만든다 — 헤더 주석 참조).
# 이 항목의 실제 검사는 observability 파드 Running 수라 부하 파드와 무관하다.
GRAFANA_LB=$(kubectl get svc -n observability -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.status.loadBalancer.ingress[0].hostname}{end}' 2>/dev/null)
for p in fluent-bit prometheus grafana; do kubectl get pods -n observability --no-headers --request-timeout=10s 2>/dev/null | grep -c "$p.*Running" | xargs -I{} echo "$p: {}"; done
echo

echo =====11-2=====
echo "Datasources:"; curl -s -u admin:'Skills$#$@!' "http://${GRAFANA_LB}/api/datasources" 2>/dev/null | python3 -c "import sys,json;[print(f'  {d[\"name\"]} ({d[\"type\"]})') for d in json.load(sys.stdin)]" 2>/dev/null || echo "  Grafana unreachable"
echo "Dashboards:"; curl -s -u admin:'Skills$#$@!' "http://${GRAFANA_LB}/api/search?query=wsc2026" 2>/dev/null | python3 -c "import sys,json;[print(f'  {d[\"title\"]}') for d in json.load(sys.stdin)]" 2>/dev/null || echo "  Not found"
echo

echo =====11-3=====
echo "수동 채점: 대시보드 구성 확인"
# 정본의 `sleep 180` 을 조건 폴링으로 대체. 이미 Firing 이면 즉시 통과한다.
echo "----- 알람 발화 대기 (정본 sleep 180 대체) -----"
wait_for_alerts
echo
echo "접속: http://${GRAFANA_LB} (admin / Skills\$#\$@!)"
echo "대시보드: wsc2026-grafana-dashboard"
echo ""
echo "아래 16개 구성 요소가 대시보드에 포함되어 있는지 확인 (최종 채점지 11-3 본문 명시)"
echo "  Node CPU (%) / Node Memory (%) / Available Nodes"
echo "  Pod CPU / Pod Memory / Pending Pods / Pod Restarts"
echo "  App Pod CPU / App Pod Memory / App Running / App Restarts / App Pending"
echo "  Request Count / Response Time / Status Code / Application Logs"
echo "모든 메트릭 및 로그는 빈값이 없어야 한다"
echo "색상: CPU 80%↑ 빨강, 60~80% 노랑, 60%↓ 초록 / Restart 1↑ 경고"
echo ""
echo "특히 확인할 것:"
echo "  Available Nodes  : 노드그룹 이름 타일 2개(wsc2026-addon-nodegroup / wsc2026-workload-ng)에"
echo "                     각각 2 — 이름 없는 타일 1개(총합 4)로 보이면 KSM 노드 라벨이 안 나온 것이다"
echo "  Application Logs : /v1/book 이외 경로(/nonexist, /delay)가 한 줄이라도 보이면 실패"
echo "  Request Count / Response Time / Status Code : 세 패널 모두 No Data 가 아니어야 한다"
echo ""
# 정본: "Application Logs 패널 로그 형식 예시 (/v1/book을 제외한 로그가 있을 경우 오답처리)"
# 채점 스스로 error-gen/latency-gen 으로 비-/v1/book 액세스 로그를 만들므로 수집 단계에서 거를 수 없다 —
# error-gen 의 404 가 wsc2026_errors_total(→ HighErrorRate 11-4, Status Code 4XX)의 유일한 공급원이다.
# 따라서 fluent-bit 은 그대로 두고 Application Logs 패널의 Insights 쿼리에서만 /v1/book 을 필터한다
# (dashboard.json id 20, 결정 로그 2026-08-22).
# 정정 2026-08-16: Pod CPU/Memory 는 All Pod 기준.
echo "Application Logs 패널 로그 형식 예시 (/v1/book 을 제외한 로그가 있을 경우 오답처리):"
echo 'INFO {"level":"INFO","path":"/v1/book","status":"200","duration":"112.663323ms","method":"POST"}'
echo

echo =====11-4=====
echo "수동 채점: Alert 확인"
# 최종 채점지 본문 명시: "(* HighLatency Alert 구성요소는 채점과 무관합니다.)" — 5종만 확인한다.
echo "Alerts 로우에서 아래 5개가 빨간색(Firing)으로 표시되는지 확인"
echo "  PodHighCPU / PodHighMemory / PodNotReady / HighErrorRate / PodCrashLooping"
echo
echo
