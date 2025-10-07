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

locals {
  # Hash app sources and Dockerfile to produce a stable tag per change
  app_hash        = sha1(join("", [for f in fileset("${path.module}/../app", "**") : filesha1("${path.module}/../app/${f}")]))
  dockerfile_hash = filesha256("${path.module}/../Dockerfile")
  # If auto_tag is true, derive a unique tag from content; else honor user-provided tag literally
  image_tag_effective = var.auto_tag ? substr(sha1("${local.dockerfile_hash}${local.app_hash}"), 0, 12) : var.image_tag
}

# --- Networking ---
resource "aws_vpc" "rem" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  tags                 = { Name = "rem-vpc" }
}

resource "aws_internet_gateway" "rem" {
  vpc_id = aws_vpc.rem.id
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.rem.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, 0)
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]
  tags                    = { Name = "rem-public-a" }
}

# Add a second public subnet for ALB multi-AZ
resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.rem.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, 1)
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[1]
  tags                    = { Name = "rem-public-b" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.rem.id
}

resource "aws_route" "igw" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.rem.id
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# --- Security Group ---
resource "aws_security_group" "rem" {
  name        = "rem-sg"
  description = "Allow HTTP/HTTPS"
  vpc_id      = aws_vpc.rem.id

  ingress {
    description = "HTTP 80"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTP"
    from_port   = 8000
    to_port     = 8000
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

# --- IAM Role for EC2 to call AWS services (Bedrock/Polly via SDK default provider chain) ---
resource "aws_iam_role" "ec2_role" {
  name = "rem-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = { Service = "ec2.amazonaws.com" },
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "rem_policy" {
  name = "rem-ec2-perms"
  role = aws_iam_role.ec2_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # Bedrock invoke
      {
        Effect = "Allow",
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ],
        Resource = "*"
      },
      # Polly synthesize and voices
      {
        Effect = "Allow",
        Action = [
          "polly:SynthesizeSpeech",
          "polly:DescribeVoices"
        ],
        Resource = "*"
      },
      # ECR pull permissions for the instance to docker pull
      {
        Effect = "Allow",
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ],
        Resource = "*"
      },
      # Logs: allow CloudWatch agent if added later
      {
        Effect   = "Allow",
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
        Resource = "*"
      }
    ]
  })
}

# --- ECR repository to host the app image ---
resource "aws_ecr_repository" "rem" {
  name                 = var.ecr_repo_name
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = false }
  force_delete = true
}

# Build and push the Docker image locally during apply (requires Docker and AWS CLI locally)
resource "null_resource" "image_build_and_push" {
  count      = var.enable_local_image_build ? 1 : 0
  depends_on = [aws_ecr_repository.rem]
  triggers = {
    dockerfile_hash = local.dockerfile_hash
    app_hash        = local.app_hash
    image_tag       = local.image_tag_effective
  }
  provisioner "local-exec" {
    interpreter = ["bash", "-lc"]
    command     = <<-BASH
      set -euo pipefail
      REPO_URL="${aws_ecr_repository.rem.repository_url}"
      REGION="${var.bedrock_region}"
      TAG="${local.image_tag_effective}"
      # Extract registry safely without bash parameter expansion in Terraform templates
      REGISTRY=$(printf "%s" "$REPO_URL" | cut -d'/' -f1)

      aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"

      CTX_DIR="${path.module}/../"
      cd "$CTX_DIR"
      docker build -t rem-app:"$TAG" --build-arg APP_BUILD=terraform-$(date +%s) .
      docker tag rem-app:"$TAG" "$REPO_URL:$TAG"
      docker push "$REPO_URL:$TAG"
    BASH
  }
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "rem-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# --- Launch Template for ASG ---
data "aws_ami" "ubuntu" {
  count       = var.ami_id == null ? 1 : 0
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_launch_template" "app" {
  name_prefix   = "rem-lt-"
  image_id      = coalesce(var.ami_id, try(data.aws_ami.ubuntu[0].id, null))
  instance_type = var.instance_type
  iam_instance_profile { name = aws_iam_instance_profile.ec2_profile.name }
  vpc_security_group_ids = [aws_security_group.rem.id]

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    ecr_repo_url         = aws_ecr_repository.rem.repository_url,
    ecr_registry         = replace(aws_ecr_repository.rem.repository_url, "/.*$", ""),
    image_tag            = local.image_tag_effective,
    bedrock_region       = var.bedrock_region,
    bedrock_model        = var.bedrock_model,
    polly_region         = var.polly_region,
    polly_voice          = var.polly_voice,
    bedrock_max_retries  = var.bedrock_max_retries,
    chat_max_concurrency = var.chat_max_concurrency,
    tts_max_concurrency  = var.tts_max_concurrency,
    tts_cache_ttl        = var.tts_cache_ttl,
    uvicorn_workers      = var.uvicorn_workers
  }))

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "rem-app", RefreshNonce = var.refresh_nonce }
  }
}

# --- ALB + Target Group ---
resource "aws_lb" "app" {
  name               = "rem-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.rem.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  idle_timeout       = var.alb_idle_timeout
}

resource "aws_lb_target_group" "app" {
  name     = "rem-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.rem.id
  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 5
    interval            = 15
    timeout             = 5
    path                = "/api/health"
    matcher             = "200"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# --- Auto Scaling Group ---
resource "aws_autoscaling_group" "app" {
  name                      = "rem-asg"
  desired_capacity          = var.asg_desired
  max_size                  = var.asg_max
  min_size                  = var.asg_min
  vpc_zone_identifier       = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  health_check_type         = "ELB"
  health_check_grace_period = 60
  target_group_arns         = [aws_lb_target_group.app.arn]

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "rem-asg"
    propagate_at_launch = true
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 60
    }
    triggers = ["launch_template"]
  }
}

# Optional: force an instance refresh each apply when using a static image tag like 'latest'
// forced ASG refresh removed to simplify destroy/apply on Windows

resource "aws_autoscaling_policy" "cpu_target" {
  name                   = "cpu-target-60"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 60
  }
}

resource "aws_autoscaling_policy" "alb_req_per_target" {
  name                   = "alb-requests-per-target"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.app.arn_suffix}/${aws_lb_target_group.app.arn_suffix}"
    }
    target_value = var.target_requests_per_instance
  }
}

# Auto-write vercel.json with the current ALB DNS after apply
resource "null_resource" "write_vercel_json" {
  triggers = {
    alb_dns = aws_lb.app.dns_name
  }
  provisioner "local-exec" {
    interpreter = ["bash", "-lc"]
    command     = <<-BASH
      set -euo pipefail
      ROOT="${path.module}/../"
  cat > "$${ROOT}/vercel.json" <<'EOT'
{
  "version": 2,
  "routes": [
    { "src": "/api/(.*)", "dest": "http://${aws_lb.app.dns_name}/api/$1" },
    { "src": "/(.*)",    "dest": "http://${aws_lb.app.dns_name}/$1" }
  ]
}
EOT
    BASH
  }
}

data "aws_availability_zones" "available" {}
