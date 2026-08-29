module "eks" {
    source = "terraform-aws-modules/eks/aws"
    version = "~> 20.0"

    cluster_name = var.cluster-name
    cluster_version = var.cluster-version

    cluster_endpoint_public_access = true
    enable_cluster_creator_admin_permissions = true

    vpc_id = module.vpc.vpc_id
    subnet_ids = module.vpc.private_subnets
    

    eks_managed_node_groups = {
        general_nodes = {
            min_size = 1
            max_size = 4
            desired_size = 2

            instance_types = [var.instance_types]
            

        }
    }

    tags = var.tags 
    
}