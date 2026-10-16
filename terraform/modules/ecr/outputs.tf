output "repository_urls" {
  value = {
    for name, repo in aws_ecr_repository.ecr-repo :
    name => repo.repository_url
  }
}

output "repository_arns" {
  value = [
    for repo in aws_ecr_repository.ecr-repo :
    repo.arn
  ]
}

output "repository_names" {
  value = keys(aws_ecr_repository.ecr-repo)
}
