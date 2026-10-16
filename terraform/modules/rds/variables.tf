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

variable "vpc_id" {
  type = string
}

variable "db_subnet_ids" {
  type = list(string)
}

variable "source_security_group_id" {
  type = string
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "final_snapshot_identifier" {
  type = string
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
