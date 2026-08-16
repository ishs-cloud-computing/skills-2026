#!/usr/bin/env bash
set -u
export AWS_PAGER=""

OUT_TXT="asgmt2_module2_check_result.txt"
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

install_base_tools curl unzip
install_aws_cli


echo "== 제2과제 2모듈 Simplify Service Networking with VPC Lattice 채점 출력 =="
echo

echo "[2-1] 기본 VPC 구성 (1.5점)"
aws ec2 describe-vpcs --region ap-northeast-1 --filters Name=tag:Name,Values=skills-lattice-client-vpc,skills-lattice-service-vpc --query 'Vpcs[].{Name:Tags[?Key==`Name`].Value|[0],VpcId:VpcId,Cidr:CidrBlock,State:State}' --output table
CLIENT_VPC_ID=$(aws ec2 describe-vpcs --region ap-northeast-1 --filters Name=tag:Name,Values=skills-lattice-client-vpc --query 'Vpcs[0].VpcId' --output text 2>/dev/null || true)
SERVICE_VPC_ID=$(aws ec2 describe-vpcs --region ap-northeast-1 --filters Name=tag:Name,Values=skills-lattice-service-vpc --query 'Vpcs[0].VpcId' --output text 2>/dev/null || true)
echo "CLIENT_VPC_ID=${CLIENT_VPC_ID}"
echo "SERVICE_VPC_ID=${SERVICE_VPC_ID}"
if [ -n "$CLIENT_VPC_ID" ] && [ "$CLIENT_VPC_ID" != "None" ] && [ -n "$SERVICE_VPC_ID" ] && [ "$SERVICE_VPC_ID" != "None" ]; then
  aws ec2 describe-subnets --region ap-northeast-1 --filters Name=vpc-id,Values="$CLIENT_VPC_ID","$SERVICE_VPC_ID" --query 'Subnets[].{SubnetId:SubnetId,VpcId:VpcId,Cidr:CidrBlock,AZ:AvailabilityZone,MapPublicIp:MapPublicIpOnLaunch,Name:Tags[?Key==`Name`].Value|[0]}' --output table
else
  echo "Client 또는 Service VPC 식별 실패"
fi

echo
echo "[2-2] Client/Service EC2 및 애플리케이션 구성 (1.5점)"
aws ec2 describe-instances --region ap-northeast-1 --filters Name=tag:Name,Values=skills-lattice-client-ec2,skills-lattice-service-ec2 Name=instance-state-name,Values=running --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`].Value|[0],Id:InstanceId,Type:InstanceType,PublicIp:PublicIpAddress,PrivateIp:PrivateIpAddress,State:State.Name}' --output table
LATTICE_CLIENT_EC2_PUBLIC_IP=$(aws ec2 describe-instances --region ap-northeast-1 --filters Name=tag:Name,Values=skills-lattice-client-ec2 Name=instance-state-name,Values=running --query 'Reservations[0].Instances[0].PublicIpAddress' --output text 2>/dev/null || true)
SERVICE_INSTANCE_ID=$(aws ec2 describe-instances --region ap-northeast-1 --filters Name=tag:Name,Values=skills-lattice-service-ec2 Name=instance-state-name,Values=running --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null || true)
SERVICE_SG_IDS=$(aws ec2 describe-instances --region ap-northeast-1 --filters Name=tag:Name,Values=skills-lattice-service-ec2 Name=instance-state-name,Values=running --query 'Reservations[0].Instances[0].SecurityGroups[].GroupId' --output text 2>/dev/null || true)
echo "LATTICE_CLIENT_EC2_PUBLIC_IP=${LATTICE_CLIENT_EC2_PUBLIC_IP}"
echo "SERVICE_INSTANCE_ID=${SERVICE_INSTANCE_ID}"
echo "SERVICE_SG_IDS=${SERVICE_SG_IDS}"
if [ -n "$LATTICE_CLIENT_EC2_PUBLIC_IP" ] && [ "$LATTICE_CLIENT_EC2_PUBLIC_IP" != "None" ]; then
  curl -s -m 10 -w "\nhttp_code=%{http_code}\n" "http://${LATTICE_CLIENT_EC2_PUBLIC_IP}/health"; echo
else
  echo "Client EC2 Public IP 식별 실패"
fi

SERVICE_NETWORK_ID=$(aws vpc-lattice list-service-networks --region ap-northeast-1 --query 'items[?name==`skills-lattice-sn`].id|[0]' --output text 2>/dev/null || true)
SERVICE_ID=$(aws vpc-lattice list-services --region ap-northeast-1 --query 'items[?name==`skills-lattice-order-service`].id|[0]' --output text 2>/dev/null || true)
TARGET_GROUP_ID=$(aws vpc-lattice list-target-groups --region ap-northeast-1 --query 'items[?name==`skills-lattice-order-tg`].id|[0]' --output text 2>/dev/null || true)
echo
echo "[2-3] VPC Lattice Service Network 및 Service 구성 (1.5점)"
echo "SERVICE_NETWORK_ID=${SERVICE_NETWORK_ID}"
echo "SERVICE_ID=${SERVICE_ID}"
aws vpc-lattice list-service-networks --region ap-northeast-1 --query 'items[?name==`skills-lattice-sn`].{Name:name,Id:id,AssociatedVPCs:numberOfAssociatedVPCs,AssociatedServices:numberOfAssociatedServices}' --output table
aws vpc-lattice list-services --region ap-northeast-1 --query 'items[?name==`skills-lattice-order-service`].{Name:name,Id:id,Dns:dnsEntry.domainName,Status:status}' --output table
if [ -n "$SERVICE_NETWORK_ID" ] && [ "$SERVICE_NETWORK_ID" != "None" ]; then
  aws vpc-lattice list-service-network-vpc-associations --region ap-northeast-1 --service-network-identifier "$SERVICE_NETWORK_ID" --query 'items[].{AssociationId:id,VpcId:vpcId,Status:status}' --output table
  VPC_ASSOCIATION_ID=$(aws vpc-lattice list-service-network-vpc-associations --region ap-northeast-1 --service-network-identifier "$SERVICE_NETWORK_ID" --query 'items[0].id' --output text 2>/dev/null || true)
  echo "VPC_ASSOCIATION_ID=${VPC_ASSOCIATION_ID}"
  if [ -n "$VPC_ASSOCIATION_ID" ] && [ "$VPC_ASSOCIATION_ID" != "None" ]; then
    aws vpc-lattice get-service-network-vpc-association --region ap-northeast-1 --service-network-vpc-association-identifier "$VPC_ASSOCIATION_ID" --query '{AssociationId:id,VpcId:vpcId,Status:status,SecurityGroupIds:securityGroupIds}' --output table
  fi
  aws vpc-lattice list-service-network-service-associations --region ap-northeast-1 --service-network-identifier "$SERVICE_NETWORK_ID" --query 'items[].{ServiceId:serviceId,Status:status,Dns:dnsEntry.domainName}' --output table
else
  echo "skills-lattice-sn Service Network 식별 실패"
fi

echo
echo "[2-4] Target Group, Listener, Security Group 구성 (1.5점)"
echo "TARGET_GROUP_ID=${TARGET_GROUP_ID}"
aws vpc-lattice list-target-groups --region ap-northeast-1 --query 'items[?name==`skills-lattice-order-tg`].{Name:name,Id:id,Type:type,Port:port,Protocol:protocol,Vpc:vpcIdentifier,Status:status}' --output table
if [ -n "$TARGET_GROUP_ID" ] && [ "$TARGET_GROUP_ID" != "None" ]; then
  aws vpc-lattice list-targets --region ap-northeast-1 --target-group-identifier "$TARGET_GROUP_ID" --query 'items[].{Target:id,Port:port,Status:status}' --output table
else
  echo "skills-lattice-order-tg Target Group 식별 실패"
fi
if [ -n "$SERVICE_ID" ] && [ "$SERVICE_ID" != "None" ]; then
  aws vpc-lattice list-listeners --region ap-northeast-1 --service-identifier "$SERVICE_ID" --query 'items[?name==`skills-lattice-http-listener`].{Name:name,Id:id,Port:port,Protocol:protocol}' --output table
else
  echo "skills-lattice-order-service Service 식별 실패"
fi
if [ -n "$SERVICE_SG_IDS" ] && [ "$SERVICE_SG_IDS" != "None" ]; then
  aws ec2 describe-security-groups --region ap-northeast-1 --group-ids $SERVICE_SG_IDS --query 'SecurityGroups[].{GroupId:GroupId,GroupName:GroupName,VpcId:VpcId,Inbound:IpPermissions}' --output json
else
  echo "Service EC2 Security Group 식별 실패"
fi

echo
echo "[2-5] End-to-End 기능 검증 (1.5점)"
if [ -n "$LATTICE_CLIENT_EC2_PUBLIC_IP" ] && [ "$LATTICE_CLIENT_EC2_PUBLIC_IP" != "None" ]; then
  curl -s -m 10 -w "\nhttp_code=%{http_code}\n" "http://${LATTICE_CLIENT_EC2_PUBLIC_IP}/v1/client/orders?id=1001"; echo
else
  echo "Client EC2 Public IP 식별 실패"
fi

echo
echo "Result file: ${OUT_TXT}"
