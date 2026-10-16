output "vpc_id" {
  value = aws_vpc.my-vpc.id
}

output "vpc_cidr" {
  value = aws_vpc.my-vpc.cidr_block
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_app_subnet_ids" {
  value = aws_subnet.private_app[*].id
}

output "private_db_subnet_ids" {
  value = aws_subnet.private_db[*].id
}

output "nat_gateway_id" {
  value = aws_nat_gateway.my-nat-gw.id
}
