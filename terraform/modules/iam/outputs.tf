output "cluster_role_arn" {
  value = aws_iam_role.eks_cluster.arn

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster
  ]
}

output "node_role_arn" {
  value = aws_iam_role.eks_node.arn

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_ecr,
    aws_iam_role_policy_attachment.node_cni
  ]
}

output "product_s3_access_key_id" {
  value     = aws_iam_access_key.product_s3.id
  sensitive = true
}

output "product_s3_secret_access_key" {
  value     = aws_iam_access_key.product_s3.secret
  sensitive = true
}
