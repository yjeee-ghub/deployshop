#####################################
#Terraform 및 AWS Provider 버전 설정#
#####################################

//사용 할 terraform의 버전 지정
//설치된 Terraform CLI가 1.16.0 이상인지 검사
terraform {
  required_version = ">= 1.6.0"

  //AWS Provider 6.x 버전을 설치하도록 지정
  required_providers {
    aws = {
      //AWS Provider 공식 배포 경로
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
