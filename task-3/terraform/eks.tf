# 내장 NodePool을 모두 끄면 default NodeClass가 자동 생성되지 않으므로,
# 커스텀 NodeClass가 참조할 노드 IAM 역할을 직접 만든다.
data "aws_iam_policy_document" "automode_node_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "automode_node" {
  name               = "${var.cluster_name}-automode-node"
  assume_role_policy = data.aws_iam_policy_document.automode_node_assume.json
}

resource "aws_iam_role_policy_attachment" "node_minimal" {
  role       = aws_iam_role.automode_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodeMinimalPolicy"
}

resource "aws_iam_role_policy_attachment" "node_ecr_pull" {
  role       = aws_iam_role.automode_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
}
