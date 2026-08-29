output "cluster-endpoint" {
    value = module.eks.cluster_endpoint
  
}

output "cluster_name" {
    value = module.eks.cluster_name
}

output "cluster_security_group_id" {
    value = module.eks.cluster_security_group_id
  
}

output "configure_kubectl" {
  description = "Point kubectl at the new cluster"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}