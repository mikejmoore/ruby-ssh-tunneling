################################################################################
#  AWS provider tells Terraform how to connect to your AWS account.
################################################################################

provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region     = "${var.aws_region}"
}


################################################################################
#  Set up a VPC and Subnets for our infrastucture.
################################################################################

resource "aws_vpc" "main" {
  cidr_block       = "10.0.0.0/16"
  tags {
    Name = "example-vpc"
  }
}

################################################################################
#  Gateway to/from internet.
################################################################################

resource "aws_internet_gateway" "gw" {
  vpc_id      = "${aws_vpc.main.id}"
  tags {
    Name           = "example-igw"
    environment    = "example"
    service        = "internet-gateway"
  }
}



################################################################################
#  NAT for private subnet to reach internet.
################################################################################

resource "aws_eip" "nat" {
  vpc   = true
}

resource "aws_nat_gateway" "nat_for_private" {
  allocation_id   = "${aws_eip.nat.id}"
  subnet_id       = "${aws_subnet.public.id}"
  depends_on      = ["aws_internet_gateway.gw"]
}


################################################################################
#  Subnets and routing.
################################################################################

resource "aws_route_table" "public" {
  vpc_id    = "${aws_vpc.main.id}"
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.gw.id}"
  }
  tags {
    Name           = "example-routes"
    environment    = "example"
    service        = "route-table"
  }
}

resource "aws_subnet" "public" {
  vpc_id            = "${aws_vpc.main.id}"
  availability_zone = "${var.aws_region}a"
  cidr_block        = "${cidrsubnet(aws_vpc.main.cidr_block, 4, 1)}"
  tags {
    Name          = "example-public-subnet-az-a"
    environment   = "example"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id         = "${aws_subnet.public.id}"
  route_table_id    = "${aws_route_table.public.id}"
}

resource "aws_route_table" "private" {
  vpc_id    = "${aws_vpc.main.id}"
  route {
    cidr_block        = "0.0.0.0/0"
    nat_gateway_id    = "${aws_nat_gateway.nat_for_private.id}"
  }
  tags {
    Name           = "example-private-routes"
    environment    = "example"
    service        = "route-table"
  }
}

resource "aws_subnet" "private" {
  vpc_id            = "${aws_vpc.main.id}"
  availability_zone = "${var.aws_region}b"
  cidr_block        = "${cidrsubnet(aws_vpc.main.cidr_block, 4, 2)}"
  tags {
    Name          = "example-private-subnet-az-b"
    environment   = "example"
  }
}

resource "aws_route_table_association" "subnet-private" {
  subnet_id         = "${aws_subnet.private.id}"
  route_table_id    = "${aws_route_table.private.id}"
}

################################################################################
#  Security group for the bastion.
#   * Allows SSH from anywhere.
################################################################################

resource "aws_security_group" "bastion" {
  name        = "example-1-nginx-instance-sec-group"
  vpc_id      = "${aws_vpc.main.id}"
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags {
    Name          = "example-bastion-sec-group"
    service       = "bastion"
    environment   = "example"
  }
}

data "aws_ami" "amazon-linux" {
  most_recent = true
  filter {
    name   = "name"
    values = ["Amazon Linux AMI 2017.09.0.20170930*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

################################################################################
#  Create the Bastion EC2 Instance in the public subnet.
################################################################################

resource "aws_instance" "bastion" {
  ami                     = "${data.aws_ami.amazon-linux.id}"
  instance_type           = "t2.nano"
  subnet_id               =  "${aws_subnet.public.id}"
  vpc_security_group_ids  = ["${aws_security_group.bastion.id}"]
  key_name                = "${var.key_pair}"
  associate_public_ip_address = true
  tags {
    Name          = "example-bastion"
    environment   = "example"
    service       = "bastion"
  }
}

################################################################################
#  Security group for private instances.  Can only be reached by bastion.
################################################################################

resource "aws_security_group" "private_ssh" {
  name        = "example-private-ssh-sg"
  vpc_id      = "${aws_vpc.main.id}"
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${aws_vpc.main.cidr_block}"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags {
    Name          = "example-private-sec-group"
    service       = "all-services"
    environment   = "example"
  }
}

################################################################################
#  Create an EC2 Instance that might provide a backing service.  Put it in
#  a private subnet for security reasons.  It can only be SSH'ed through
#  the Bastion.
################################################################################

resource "aws_instance" "private_instance_1" {
  ami                       = "${data.aws_ami.amazon-linux.id}"
  instance_type             = "t2.nano"
  subnet_id                 =  "${aws_subnet.private.id}"
  vpc_security_group_ids    = ["${aws_security_group.private_ssh.id}"]
  key_name                  = "${var.key_pair}"
  associate_public_ip_address = false
  tags {
    Name          = "example-private-instance-1"
    environment   = "example"
    service       = "service-1"
  }
}
