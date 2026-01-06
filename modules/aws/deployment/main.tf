resource "aws_vpc" "main_vpc" {
  count = var.use_existing_vpc ? 0 : 1

  cidr_block = var.cidr_block
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = merge(var.tags, {
    Name = var.use_existing_vpc ? var.existing_vpc_id : join("-", [var.name, "vpc", var.random_string_salt])
  })
}

data "aws_vpc" "vpc" {

  id = var.use_existing_vpc ? var.existing_vpc_id : aws_vpc.main_vpc[0].id
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "random_shuffle" "aws_availability_zone_names" {
  input        = data.aws_availability_zones.available.names
  result_count = 2
}

resource "aws_internet_gateway" "igw" {
  count = var.use_existing_vpc ? 0 : 1

  vpc_id = data.aws_vpc.vpc.id
  tags = merge(var.tags, {
    Name = join("-", [var.name, var.random_string_salt, "igw"])
  })
  
}

resource "aws_route_table" "public" {
  count = var.use_existing_vpc ? 0 : 1

  vpc_id = data.aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw[count.index].id
  }
  tags = merge(var.tags, {
    Name = join("-", [var.name, var.random_string_salt, "public", "route", "table"])
  })
}

resource "aws_subnet" "public_subnet" {
  count = var.use_existing_subnet ? 0 : 2

  vpc_id     = data.aws_vpc.vpc.id
  cidr_block = cidrsubnet(data.aws_vpc.vpc.cidr_block, 8, 0 + count.index)
  availability_zone = element(random_shuffle.aws_availability_zone_names.result, count.index)
  map_public_ip_on_launch = true
  tags = merge(var.tags, {
    Name = join("-", [var.name, var.random_string_salt, "public", "subnet", count.index])
  })
}

resource "aws_subnet" "private_subnet" {
  count = var.use_existing_subnet ? 0 : 2

  vpc_id     = data.aws_vpc.vpc.id
  cidr_block = cidrsubnet(data.aws_vpc.vpc.cidr_block, 8, 2 + count.index)
  availability_zone = element(random_shuffle.aws_availability_zone_names.result, count.index)
  map_public_ip_on_launch = false
  tags = merge(var.tags, {
    Name = join("-", [var.name, var.random_string_salt, "private", "subnet", count.index])
  })
}

resource "aws_eip" "nat" {
  count = var.use_existing_subnet ? 0 : 2

  domain = "vpc"
  tags = merge(var.tags, {
    Name = join("-", [var.name, var.random_string_salt, "nat", "eip", count.index])
  })

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_nat_gateway" "nat" {
  count = var.use_existing_subnet ? 0 : 2

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public_subnet[count.index].id

  tags = merge(var.tags, {
    Name = join("-", [var.name, var.random_string_salt, "nat", "gateway", count.index])
  })

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route_table" "private" {
  count = var.use_existing_subnet ? 0 : 2

  vpc_id = data.aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat[count.index].id
  }
  tags = merge(var.tags, {
    Name = join("-", [var.name, var.random_string_salt, "private", "route", "table", count.index])
  })
}

resource "aws_route_table_association" "public_subnet_association" {
  count = var.use_existing_subnet ? 0 : 2
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_route_table_association" "private_subnet_association" {
  count = var.use_existing_subnet ? 0 : 2
  subnet_id      = aws_subnet.private_subnet[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

resource "aws_security_group" "k8s_security_group" {
  name        = join("-", [var.name, var.random_string_salt, "k8s", "sg"])
  description = "Egress rules for EKS cluster"
  vpc_id      = data.aws_vpc.vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(var.tags, {
    Name = join("-", [var.name, var.random_string_salt, "k8s", "sg"])
  })

}

