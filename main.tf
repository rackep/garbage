#####################################
##### Input values for provider #####
#####################################

# Input values for provider
provider "aws" {
    region     = "${var.region}"
    profile    = "${var.profile}"
} 
# end provider

###############
##### VPC #####
###############

resource "aws_vpc" "myVpc" {
    for_each = var.networks

    cidr_block = each.value.base_cidr_block

    tags = {
        # Name = "dev-myvpc"
        Name = "${var.envPrefix}-${each.key}"
    }
}

locals {
    # setproduct works with sets and lists, but the variables are both maps
    # so convert them first.
    networks = [
        for key, network in var.networks : {
        key        = key
        cidr_block = network.base_cidr_block
        }
    ]
    subnets = [
        for key, subnet in var.subnets : {
        key    = key
        number = subnet.number
        }
    ]

    network_subnets = [
        # in pair, element zero is a network and element one is a subnet,
        # in all unique combinations.
        for pair in setproduct(local.networks, local.subnets) : {
            network_key     = pair[0].key # myvpc, egress
            subnet_key      = pair[1].key # a, b
            subnet_number   = pair[1].number # 1, 2
            network_id      = aws_vpc.myVpc[pair[0].key].id
            duzina = length(pair[1])

            # The cidr_block is derived from the corresponding network. Refer to the
            # cidrsubnet function for more information on how this calculation works.
            cidr_block_public   = cidrsubnet(pair[0].cidr_block, 8, pair[1].number*4 - 4) # -4 offset to .0.0/24 and .4.0/24
            cidr_block_private  = cidrsubnet(pair[0].cidr_block, 8, pair[1].number*4 - 4 + 8) # -4 + 8 offset to .8.0/24 and .12.0/24
            cidr_block_isolated = cidrsubnet(pair[0].cidr_block, 8, pair[1].number*4 -4 + 12) # -4 + 12 offset to .16.0/24 and .20.0/24
        }
    ]
}


###################
##### SUBNETS #####
###################

resource "aws_subnet" "publicSubnet" {
    # local.network_subnets is a list, so project it into a map
    # where each key is unique. Combine the network and subnet keys to
    # produce a single unique key per instance.
    for_each = {
        for subnet in local.network_subnets : "${subnet.network_key}.${subnet.subnet_key}" => subnet
    }

    vpc_id                  = each.value.network_id
    availability_zone       = "${var.region}${each.value.subnet_key}" # ${eu-central-1}${a}
    cidr_block              = each.value.cidr_block_public
    map_public_ip_on_launch = true

    tags = {
        # Name = "dev-myvpc-public-subnet-1"
        Name = "${var.envPrefix}-${each.value.network_key}-public-subnet-${each.value.subnet_number}"
    }
}

resource "aws_subnet" "privateSubnet" {
    # local.network_subnets is a list, so project it into a map
    # where each key is unique. Combine the network and subnet keys to
    # produce a single unique key per instance.
    for_each = {
        for subnet in local.network_subnets : "${subnet.network_key}.${subnet.subnet_key}" => subnet
    }

    vpc_id                  = each.value.network_id
    availability_zone       = "${var.region}${each.value.subnet_key}"
    cidr_block              = each.value.cidr_block_private
    map_public_ip_on_launch = false

    tags = {
        # Name = "dev-myvpc-private-subnet-1"
        Name = "${var.envPrefix}-${each.value.network_key}-private-subnet-${each.value.subnet_number}"
    }
}



output "vpc_subnets" {
    value = {
        for_each = {
            for subnet in local.network_subnets : "${subnet.network_key}.${subnet.subnet_key}" => subnet
        }
    }
}

output "vpc_ids" {
    value = {
        for k, v in aws_vpc.myVpc : k => v.id # eggress = vpc_id
    }
}

output "vpc_tags" {
    value = {
        for k, v in aws_vpc.myVpc : k => k # eggress = "eggress"
        # for k, v in aws_vpc.myVpc : k => v.tags["Name"]
    }
}


data "aws_availability_zones" "available" {}
output "zzz" {
    # value = "${length(data.aws_availability_zones.available.names)}"
    value = "${length(var.subnets)}"
}
