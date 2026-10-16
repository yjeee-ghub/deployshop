#############################
# VPC
#############################

resource "aws_vpc" "my-vpc" {
  cidr_block = var.vpc_cidr

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}


#############################
# Internet Gateway
#############################

resource "aws_internet_gateway" "my-igw" {
  vpc_id = aws_vpc.my-vpc.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}


#############################
# Public Subnets
//Nat GW에 사용
//LB에 사용(EKS 배포용)
//SSH  접속용(Bastion Host)
#############################

resource "aws_subnet" "public" {
  count = length(var.azs)

  vpc_id            = aws_vpc.my-vpc.id
  availability_zone = var.azs[count.index]
  cidr_block        = var.public_subnet_cidrs[count.index]

  map_public_ip_on_launch = true

  tags = {
    Name                     = "${var.project_name}-public-${count.index + 1}"
    "kubernetes.io/role/elb" = "1"
  }
}


#############################
# Private App Subnets
#############################

resource "aws_subnet" "private_app" {
  count = length(var.azs)

  vpc_id            = aws_vpc.my-vpc.id
  availability_zone = var.azs[count.index]
  cidr_block        = var.private_app_subnet_cidrs[count.index]

  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-app-${count.index + 1}"

    "kubernetes.io/role/internal-elb" = "1"
  }
}


#############################
# Private DB Subnets
#############################

resource "aws_subnet" "private_db" {
  count = length(var.azs)

  vpc_id            = aws_vpc.my-vpc.id
  availability_zone = var.azs[count.index]
  cidr_block        = var.private_db_subnet_cidrs[count.index]

  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-db-${count.index + 1}"
  }
}


#############################
# Public Route Table
//나가고 들어오는 외부 통신 가능
//IGW를 라우팅 테이블에 등록
#############################

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.my-vpc.id

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route" "public_internet" {
  route_table_id = aws_route_table.public.id

  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.my-igw.id
}

resource "aws_route_table_association" "public" {
  count = length(var.azs)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}


#############################
# NAT Gateway
#############################

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip"
  }
}

resource "aws_nat_gateway" "my-nat-gw" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  depends_on = [
    aws_internet_gateway.my-igw
  ]

  tags = {
    Name = "${var.project_name}-nat"
  }
}


#############################
# Private App Route Table
//Private이지만 간헐적인 인터넷 통신이 필요
//나가는 외부 통신은 가능, 들어오는 외부 통신은 불가능
//ECR에서 Docker 이미지 다운로드, 외부 API 호출, 노드가 필요한 패키지나 업데이트 다운로드 등
#############################

resource "aws_route_table" "private_app" {
  vpc_id = aws_vpc.my-vpc.id

  tags = {
    Name = "${var.project_name}-app-rt"
  }
}

// App Subnet의 외부 인터넷 통신을 위한 NAT 경로
resource "aws_route" "private_app_nat" {
  route_table_id = aws_route_table.private_app.id

  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.my-nat-gw.id
}

// 서브넷과 route table연결
resource "aws_route_table_association" "private_app" {
  count = length(var.azs)

  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private_app.id
}


#############################
# Private DB Route Table
//Private Only
#############################

resource "aws_route_table" "private_db" {
  vpc_id = aws_vpc.my-vpc.id

  tags = {
    Name = "${var.project_name}-db-rt"
  }
}

resource "aws_route_table_association" "private_db" {
  count = length(var.azs)

  subnet_id      = aws_subnet.private_db[count.index].id
  route_table_id = aws_route_table.private_db.id
}
