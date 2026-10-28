terraform{
     required_providers{
	aws={
	   source="hashicorp/aws"
	   version="~>5.0"
	}
   }

}
provider "aws" {
     region="eu-central-1"	
}

resource "aws_vpc" "main" {
   cidr_block = "10.0.0.0/16"
   enable_dns_hostnames = true
   enable_dns_support = true

   tags = {
    Name = "devops-portfolio-vpc"
  } 
}

resource "aws_internet_gateway" "gw" {
   vpc_id = aws_vpc.main.id
   
   tags = {
     Name = "devops-igw"
  } 
}

resource "aws_subnet" "public" {
  vpc_id = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "eu-central-1a"
  map_public_ip_on_launch = true

  tags ={
    Name = "devops-public-subnet"	
  }
}

resource "aws_subnet" "private" {
  vpc_id = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "eu-central-1a"
 
  tags ={
    Name = "devops-private-subnet"
 }
} 

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "devops-nat-eip"
} 
}

resource "aws_nat_gateway" "nat" {
   allocation_id = aws_eip.nat.id
   subnet_id = aws_subnet.public.id

   tags = {
   Name = "devops-nat-gateway"
}
   depends_on = [aws_internet_gateway.gw]
}


resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
  cidr_block = "0.0.0.0/0"
  gateway_id  = aws_internet_gateway.gw.id
}
  tags = {
  Name = "devops-public-rt"
}
}

resource "aws_route_table" "private" {
   vpc_id = aws_vpc.main.id
   route {
   cidr_block ="0.0.0.0/0"
   nat_gateway_id = aws_nat_gateway.nat.id
}
   tags = {
   Name = "devops-private-rt"
}
}

resource "aws_route_table_association" "public" {
   subnet_id = aws_subnet.public.id
   route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
   subnet_id = aws_subnet.private.id
   route_table_id = aws_route_table.private.id
}

resource "aws_instance" "web_public" {
	ami = "ami-07a52e291ed653aa8"
	instance_type = "t3.micro"
	subnet_id = aws_subnet.public.id
}

resource "aws_instance" "app_private" {
	ami = "ami-07a52e291ed653aa8"
	instance_type = "t3.micro"
	subnet_id = aws_subnet.private.id
}

resource "local_file" "ansible_inventory" {
  content = <<-EOT
    [web_servers]
    ${aws_instance.web_public.public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_ed25519

    [private_servers]
    server_privat ansible_host=${aws_instance.app_private.private_ip}

    [private_servers:vars]
    ansible_user=ubuntu
    ansible_ssh_private_key_file=~/.ssh/id_ed25519
    ansible_ssh_common_args='-o ProxyJump=ubuntu@${aws_instance.web_public.public_ip} -o StrictHostKeyChecking=no'
    ansible_become=true
    ansible_become_method=sudo
    ansible_become_pass=""
  EOT
  filename = "${path.module}/inventory"
}
