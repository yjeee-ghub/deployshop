# 현재 AWS 계정
output "aws_account_id" {
  value = data.aws_caller_identity.current.account_id
}

# VPC
output "vpc_id" {
  value = module.network.vpc_id
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "private_app_subnet_ids" {
  value = module.network.private_app_subnet_ids
}

output "private_db_subnet_ids" {
  value = module.network.private_db_subnet_ids
}

# EKS
output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "eks_node_group_name" {
  value = module.eks.node_group_name
}

# RDS
output "rds_endpoint" {
  value = module.rds.db_endpoint
}

output "rds_address" {
  value = module.rds.db_address
}

# ECR
output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

# S3
output "s3_bucket_name" {
  value = module.s3.bucket_name
}

# 상품 이미지용 IAM 자격 증명
output "product_s3_access_key_id" {
  value     = module.iam.product_s3_access_key_id
  sensitive = true
}

output "product_s3_secret_access_key" {
  value     = module.iam.product_s3_secret_access_key
  sensitive = true
}
