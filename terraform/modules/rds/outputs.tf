output "db_identifier" {
  value = aws_db_instance.mysql.identifier
}

output "db_endpoint" {
  value = aws_db_instance.mysql.endpoint
}

output "db_address" {
  value = aws_db_instance.mysql.address
}

output "db_port" {
  value = aws_db_instance.mysql.port
}

output "db_name" {
  value = aws_db_instance.mysql.db_name
}
