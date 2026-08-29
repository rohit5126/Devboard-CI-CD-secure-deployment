data "aws_availability_zones" "available" {  
}

module "vpc" {
    source = "terraform-aws-modules/vpc/aws"
    version = "5.8.1"

    name = "${var.cluster-name}-vpc"
    cidr = var.vpc-cidr

    azs = slice(data.aws_availability_zones.available.names, 0, 2)
    private_subnets = [var.pvt-cidr-1, var.pvt-cidr-2]
    public_subnets = [var.pub-cidr-1, var.pub-cidr-2]

    enable_nat_gateway = true
    single_nat_gateway = true
    enable_dns_hostnames = true

    public_subnet_tags = {
        "kubernetes.io/role/elb" = 1
    }

    private_subnet_tags = {
        "kubernetes.io/role/internal-elb" = 1
    }
  
}