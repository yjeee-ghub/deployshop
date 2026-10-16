#####################################
#AWS 연결 설정
#공통 계정 정보 조회
#####################################


provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  //"aws" Provider를 사용하는 리소스 전체(프로젝트 공통 태그 관리)
  //태그 기능을 지원하는 리소스에만 적용
  //만약 리소스에 직접 지정한 tags값이 생긴다면 resource tags값이 우선 적용
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = "portfolio"
      ManagedBy   = "Terraform"
    }
  }
}

//현재 로그인한 AWS 계정 정보 조회
data "aws_caller_identity" "current" {}
