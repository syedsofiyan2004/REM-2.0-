terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# --- Data Sources ---
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-*-amd64-server-*"]
  }
  
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# --- Networking (Simplified) ---
resource "aws_vpc" "rem" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  tags                 = { Name = "rem-vpc" }
}

resource "aws_internet_gateway" "rem" {
  vpc_id = aws_vpc.rem.id
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.rem.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, 0)
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]
  tags                    = { Name = "rem-public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.rem.id
}

resource "aws_route" "igw" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.rem.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# --- Security Group ---
resource "aws_security_group" "rem" {
  name_prefix = "rem-sg"
  vpc_id      = aws_vpc.rem.id
  description = "Allow HTTP/HTTPS and SSH"

  ingress {
    description = "HTTP"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP 80"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
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

# --- IAM Role for EC2 ---
resource "aws_iam_role" "ec2_role" {
  name = "rem-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "rem_policy" {
  name = "rem-ec2-perms"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "polly:SynthesizeSpeech",
          "polly:DescribeVoices"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "rem-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# --- ECR Repository ---
resource "aws_ecr_repository" "rem" {
  name                 = "rem-app"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false
  }
}

# --- Elastic IP ---
resource "aws_eip" "rem" {
  domain   = "vpc"
  instance = aws_instance.rem.id
  tags     = { Name = "rem-eip" }
}

# --- EC2 Instance ---
resource "aws_instance" "rem" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.rem.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  user_data              = base64encode(templatefile("${path.module}/user_data.sh", {
    ecr_repo_url = aws_ecr_repository.rem.repository_url
    aws_region   = var.aws_region
  }))

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
  }

  tags = {
    Name = "rem-app"
  }

  # Ensure instance is replaced when user data changes
  user_data_replace_on_change = true
}

# --- Vercel Configuration ---
resource "null_resource" "write_vercel_json" {
  triggers = {
    eip = aws_eip.rem.public_ip
  }

  provisioner "local-exec" {
    command = "echo '{\"rewrites\":[{\"source\":\"/api/(.*)\",\"destination\":\"http://${aws_eip.rem.public_ip}:8000/api/$1\"},{\"source\":\"/static/(.*)\",\"destination\":\"http://${aws_eip.rem.public_ip}:8000/static/$1\"}]}' > ${path.module}/../vercel.json"
  }
}