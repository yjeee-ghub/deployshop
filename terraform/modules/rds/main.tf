#############################
# DB Subnet Group
#############################

resource "aws_db_subnet_group" "db_subnet_group" {
  name = "${var.db_identifier}-subnet-group"

  subnet_ids = var.db_subnet_ids

  tags = {
    Name = "${var.db_identifier}-subnet-group"
  }
}


#############################
# RDS Security Group
#############################

resource "aws_security_group" "rds" {
  name        = "${var.db_identifier}-sg"
  description = "MySQL access from EKS"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.db_identifier}-sg"
  }
}


#############################
# EKS → RDS MySQL 허용
#############################

resource "aws_vpc_security_group_ingress_rule" "mysql" {
  security_group_id = aws_security_group.rds.id

  referenced_security_group_id = var.source_security_group_id

  ip_protocol = "tcp"
  from_port   = 3306
  to_port     = 3306

  description = "Allow EKS nodes to access MySQL"
}


#############################
# Workbench → RDS MySQL 허용
#############################

# Workbench 접속은 지정한 IPv4 CIDR에서 허용합니다. 실습 후 PC 공인 IP/32로 제한합니다.
resource "aws_vpc_security_group_ingress_rule" "workbench" {
  security_group_id = aws_security_group.rds.id
  cidr_ipv4         = var.workbench_allowed_cidr
  ip_protocol       = "tcp"
  from_port         = 3306
  to_port           = 3306
  description       = "MySQL access from the configured Workbench IPv4 CIDR"
}


#############################
# RDS MySQL
#############################

resource "aws_db_instance" "mysql" {
  identifier = var.db_identifier

  engine         = "mysql"
  instance_class = var.db_instance_class

  allocated_storage     = 20
  max_allocated_storage = 100

  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  port = 3306

  db_subnet_group_name = aws_db_subnet_group.db_subnet_group.name

  vpc_security_group_ids = [
    aws_security_group.rds.id
  ]

  # 개인 포트폴리오의 외부 Workbench 접속을 위해 공개 접근을 허용합니다.
  publicly_accessible = true
  multi_az            = false

  backup_retention_period = 7

  # A delete must be deliberate and retain a final snapshot.
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = false
  final_snapshot_identifier = var.final_snapshot_identifier
  apply_immediately         = false

  # EKS와 Workbench의 접속 허용 규칙을 먼저 생성합니다.
  depends_on = [
    aws_vpc_security_group_ingress_rule.mysql,
    aws_vpc_security_group_ingress_rule.workbench
  ]

  tags = {
    Name = var.db_identifier
  }
}
