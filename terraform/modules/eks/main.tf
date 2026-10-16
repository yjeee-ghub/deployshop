#############################
# EKS Cluster
#############################

resource "aws_eks_cluster" "my-cluster" {
  name    = var.cluster_name
  version = var.kubernetes_version

  role_arn = var.cluster_role_arn

  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  access_config {
    authentication_mode = "API"

    bootstrap_cluster_creator_admin_permissions = false
  }

  vpc_config {
    subnet_ids = var.private_subnet_ids

    endpoint_private_access = true
    endpoint_public_access  = true

    public_access_cidrs = var.public_access_cidrs
  }

  tags = {
    Name = var.cluster_name
  }
}


#############################
# Terraform 실행 계정의 EKS Access Entry
#############################

resource "aws_eks_access_entry" "admin" {
  cluster_name = aws_eks_cluster.my-cluster.name

  principal_arn = var.eks_admin_principal_arn
  type          = "STANDARD"
}


#############################
# EKS 관리자 권한 연결
#############################

resource "aws_eks_access_policy_association" "admin" {
  cluster_name  = aws_eks_cluster.my-cluster.name
  principal_arn = aws_eks_access_entry.admin.principal_arn

  policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}


#############################
# EKS Managed Node Group
#############################

resource "aws_eks_node_group" "my-nodes" {
  cluster_name = aws_eks_cluster.my-cluster.name

  node_group_name = var.node_group_name

  # 노드도 EKS 제어 영역과 같은 Kubernetes 마이너 버전을 사용합니다.
  version = aws_eks_cluster.my-cluster.version
  node_role_arn   = var.node_role_arn

  subnet_ids = var.private_subnet_ids

  instance_types = var.node_instance_types
  ami_type       = "AL2023_x86_64_STANDARD"
  capacity_type  = "ON_DEMAND"

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  # Cluster Autoscaler가 원하는 노드 수를 조정할 수 있도록 허용
  lifecycle {
    ignore_changes = [
      scaling_config[0].desired_size
    ]
  }

  depends_on = [
    aws_eks_access_policy_association.admin
  ]

  tags = {
    Name = var.node_group_name
  }
}


#############################
# EKS Add-ons
#############################

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.my-cluster.name
  addon_name   = "vpc-cni"

  depends_on = [
    aws_eks_node_group.my-nodes
  ]
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.my-cluster.name
  addon_name   = "coredns"

  depends_on = [
    aws_eks_node_group.my-nodes
  ]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.my-cluster.name
  addon_name   = "kube-proxy"

  depends_on = [
    aws_eks_node_group.my-nodes
  ]
}


#############################
# Cluster Autoscaler ASG 태그
#############################

resource "aws_autoscaling_group_tag" "autoscaler_enabled" {
  autoscaling_group_name = aws_eks_node_group.my-nodes.resources[0].autoscaling_groups[0].name

  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "true"
    propagate_at_launch = false
  }
}

resource "aws_autoscaling_group_tag" "autoscaler_cluster" {
  autoscaling_group_name = aws_eks_node_group.my-nodes.resources[0].autoscaling_groups[0].name

  tag {
    key                 = "k8s.io/cluster-autoscaler/${var.cluster_name}"
    value               = "owned"
    propagate_at_launch = false
  }
}
