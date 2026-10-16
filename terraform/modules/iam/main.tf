#############################
# EKS Cluster IAM Role
#############################

resource "aws_iam_role" "eks_cluster" {
  name = "${var.project_name}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"
        // STS를 통해 Role을 맡도록 허용
        Action = "sts:AssumeRole"

        // EKS 서비스가 Role을 맡도록 허용(임시 자격 증명을 획득)
        // Principal>Service -> Role을 빌려 사용할 수 있는 주체
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  role = aws_iam_role.eks_cluster.name

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}


#############################
# EKS Node Group IAM Role
#############################

resource "aws_iam_role" "eks_node" {
  name = "${var.project_name}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"
        // STS를 통해 Role을 맡도록 허용
        Action = "sts:AssumeRole"

        // EC2 인스턴스가 Role을 맡도록 허용(임시 자격 증명을 획득)
        // Principal>Service -> Role을 빌려 사용할 수 있는 주체
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}


#############################
# Node Group Policy
#############################

resource "aws_iam_role_policy_attachment" "node_worker" {
  role = aws_iam_role.eks_node.name

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  role = aws_iam_role.eks_node.name

  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role = aws_iam_role.eks_node.name

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}


#############################
# Product S3 전용 IAM User
#############################

resource "aws_iam_user" "product_s3" {
  name = "${var.project_name}-product-s3-user"
}


#############################
# Product S3 접근 권한
#############################

resource "aws_iam_user_policy" "product_s3" {
  name = "${var.project_name}-product-s3-policy"
  user = aws_iam_user.product_s3.name

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]

        Resource = [
          "${var.image_bucket_arn}/products/*"
        ]
      },
      {
        Effect = "Allow"

        Action = [
          "s3:ListBucket"
        ]

        Resource = var.image_bucket_arn

        Condition = {
          StringLike = {
            "s3:prefix" = [
              "products",
              "products/*"
            ]
          }
        }
      }
    ]
  })
}


#############################
# Product S3 Access Key
#############################

resource "aws_iam_access_key" "product_s3" {
  user = aws_iam_user.product_s3.name

  depends_on = [
    aws_iam_user_policy.product_s3
  ]
}
