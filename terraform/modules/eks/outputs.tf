output "cluster_name" {
  value = aws_eks_cluster.my-cluster.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.my-cluster.endpoint
}

output "cluster_security_group_id" {
  value = aws_eks_cluster.my-cluster.vpc_config[0].cluster_security_group_id
}

output "node_group_name" {
  value = aws_eks_node_group.my-nodes.node_group_name
}

output "node_group_status" {
  value = aws_eks_node_group.my-nodes.status
}

output "node_autoscaling_group_name" {
  value = aws_eks_node_group.my-nodes.resources[0].autoscaling_groups[0].name
}
