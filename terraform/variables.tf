################################
# AWS 기본 설정
################################
variable "aws_region" {
  type = string
}

variable "aws_profile" {
  type = string
}

variable "project_name" {
  type = string
}

################################
# Network
################################
variable "vpc_cidr" {
  type = string
}

variable "azs" {
  type = list(string)
}

variable "public_subnet_cidrs" {
  type = list(string)
}

variable "private_app_subnet_cidrs" {
  type = list(string)
}

variable "private_db_subnet_cidrs" {
  type = list(string)
}


################################
# EKS
################################

variable "cluster_name" {
  type = string
}

variable "kubernetes_version" {
  type = string
}

variable "node_group_name" {
  type = string
}

variable "node_instance_types" {
  type = list(string)
}

variable "node_desired_size" {
  type = number
}

variable "node_min_size" {
  type = number
}

variable "node_max_size" {
  type = number
}

variable "eks_public_access_cidrs" {
  type = list(string)
}

################################
# RDS
################################

variable "db_identifier" {
  type = string
}

variable "db_instance_class" {
  type = string
}

variable "db_name" {
  type = string
}

variable "db_username" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

################################
# ECR
################################

variable "ecr_repository_names" {
  type = list(string)
}

################################
# S3
################################

variable "s3_bucket_name" {
  type = string
}

variable "db_deletion_protection" {
  description = "Disable explicitly and apply before a planned DB deletion."
  type        = bool
  default     = true
}

variable "db_final_snapshot_identifier" {
  description = "Must be unique among existing RDS snapshots; change for each deletion."
  type        = string
  default     = "deployshop-final-backup"
}

# Workbench 접속에 허용할 IPv4 CIDR입니다.
# 실습 중 전체 허용이 가능하며, 검증 후 접속 PC의 공인 IP/32로 제한합니다.
variable "workbench_allowed_cidr" {
  description = "Workbench 접속을 허용할 IPv4 CIDR입니다. 실습 후 PC 공인 IP/32로 제한합니다."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.workbench_allowed_cidr))
    error_message = "유효한 IPv4 CIDR 형식으로 입력하세요."
  }
}
