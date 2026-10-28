terraform{
     required_providers{
	aws={
	   source="hashicorp/aws"
	   version="~>5.0"
	}
   }

}
provider "aws" {
     region="eu-west-2"	
}

resource "aws_vpc" "main" {
   cidr_block = "10.0.0.0/16"
   enable_dns_hostnames = true
   enable_dns_support = true

   tags = {
    Name = "devops-portfolio-vpc"
  } 
}

data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"] # Canonical
}
resource "aws_key_pair" "deployer" {
  key_name   = "devops-key-london"
  public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPg+dTRFpmXn7MByKv5+u0e7jyUE3X9E7kAM4Lnc87x6 marincristianiustinian@Marins-MacBook-Pro.local"
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
  availability_zone = "eu-west-2a"
  map_public_ip_on_launch = true

  tags ={
    Name = "devops-public-subnet"	
  }
}

resource "aws_subnet" "private" {
  vpc_id = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "eu-west-2a"
 
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
	ami = data.aws_ami.ubuntu.id
	instance_type = "t3.micro"
	subnet_id = aws_subnet.public.id
	vpc_security_group_ids = [aws_security_group.web_sg.id]
	key_name = aws_key_pair.deployer.key_name
}

resource "aws_instance" "app_private" {
	ami = data.aws_ami.ubuntu.id
	instance_type = "t3.micro"
	subnet_id = aws_subnet.private.id
	key_name = aws_key_pair.deployer.key_name
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

resource "aws_security_group" "web_sg" {
  name   = "devops-web-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5000 # sau portul pe care rulează Flask
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


