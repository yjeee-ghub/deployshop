#############################
# 1. Network Module
#############################

module "network" {
  source = "./modules/network"

  project_name = var.project_name
  cluster_name = var.cluster_name

  vpc_cidr                 = var.vpc_cidr
  azs                      = var.azs
  public_subnet_cidrs      = var.public_subnet_cidrs
  private_app_subnet_cidrs = var.private_app_subnet_cidrs
  private_db_subnet_cidrs  = var.private_db_subnet_cidrs
}


#############################
# 2. S3 Module
#############################

module "s3" {
  source = "./modules/s3"

  project_name = var.project_name
  bucket_name  = var.s3_bucket_name
}


#############################
# 3. IAM Module
#############################

module "iam" {
  source = "./modules/iam"

  project_name     = var.project_name
  image_bucket_arn = module.s3.bucket_arn
}


#############################
# 4. EKS Module
#############################

module "eks" {
  source = "./modules/eks"

  cluster_name       = var.cluster_name
  kubernetes_version = var.kubernetes_version

  private_subnet_ids = module.network.private_app_subnet_ids

  cluster_role_arn = module.iam.cluster_role_arn
  node_role_arn    = module.iam.node_role_arn

  eks_admin_principal_arn = data.aws_caller_identity.current.arn

  node_group_name     = var.node_group_name
  node_instance_types = var.node_instance_types

  node_desired_size = var.node_desired_size
  node_min_size     = var.node_min_size
  node_max_size     = var.node_max_size

  public_access_cidrs = var.eks_public_access_cidrs

  # 네트워크의 NAT·라우팅 설정과 로그 그룹이 준비된 뒤 EKS를 생성합니다.
  depends_on = [
    module.network,
    aws_cloudwatch_log_group.eks_control_plane
  ]
}


#############################
# 5. RDS Module
#############################

module "rds" {
  source = "./modules/rds"

  db_identifier     = var.db_identifier
  db_instance_class = var.db_instance_class

  db_name     = var.db_name
  db_username = var.db_username
  db_password = var.db_password

  vpc_id        = module.network.vpc_id
  db_subnet_ids = module.network.public_subnet_ids

  source_security_group_id  = module.eks.cluster_security_group_id
  deletion_protection       = var.db_deletion_protection
  final_snapshot_identifier = var.db_final_snapshot_identifier
  workbench_allowed_cidr    = var.workbench_allowed_cidr

  # 퍼블릭 서브넷의 인터넷 경로와 라우팅 연결이 완료된 뒤 RDS를 생성합니다.
  depends_on = [module.network]
}


#############################
# 6. ECR Module
#############################

module "ecr" {
  source = "./modules/ecr"

  repository_names = var.ecr_repository_names
}


