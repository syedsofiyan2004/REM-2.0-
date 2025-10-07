variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "instance_type" {
  type    = string
  default = "t3.small"
}

variable "ami_id" {
  description = "Optional custom AMI ID to use for the EC2 instance. If null, latest Ubuntu 22.04 is used."
  type        = string
  default     = null
}

// SSH disabled for simpler deploy (no login required)

# Container image config
variable "ecr_repo_name" {
  type    = string
  default = "rem-app"
}

variable "image_tag" {
  type    = string
  default = "latest"
}

# When true, compute a unique content-hash tag per code change.
# When false, use the literal image_tag value (e.g., "latest").
variable "auto_tag" {
  type    = bool
  default = false
}

# Build and push the image from Terraform locally (not recommended when CI does it).
# Leave false to avoid overwriting the CI-pushed :latest tag.
variable "enable_local_image_build" {
  type    = bool
  default = false
}

variable "bedrock_region" {
  type    = string
  default = "ap-south-1"
}

variable "bedrock_model" {
  type    = string
  default = "anthropic.claude-3-haiku-20240307-v1:0"
}

variable "polly_region" {
  type    = string
  default = "ap-south-1"
}

variable "polly_voice" {
  type    = string
  default = "Ruth"
}

# Autoscaling sizes
variable "asg_min" {
  type    = number
  default = 2
}
variable "asg_desired" {
  type    = number
  default = 2
}
variable "asg_max" {
  type    = number
  default = 6
}

# Runtime tuning
variable "bedrock_max_retries" {
  type    = number
  default = 3
}
variable "chat_max_concurrency" {
  type    = number
  default = 4
}
variable "tts_max_concurrency" {
  type    = number
  default = 3
}
variable "tts_cache_ttl" {
  type    = number
  default = 900
}

variable "uvicorn_workers" {
  type    = number
  default = 2
}

variable "alb_idle_timeout" {
  type    = number
  default = 75
}

variable "target_requests_per_instance" {
  description = "Approximate request rate per instance for scaling (ALB request count per target)."
  type        = number
  default     = 40
}

# Force an Auto Scaling Group instance refresh on every terraform apply.
# Useful when using a static image tag like "latest" so new instances pull the new image.
variable "force_instance_refresh" {
  type    = bool
  default = true
}

# Bump this to any new string (e.g., a timestamp) to start an ASG Instance Refresh via Terraform.
# Useful for a one-time roll so instances get the latest user_data (Watchtower + latest tag).
variable "refresh_nonce" {
  type    = string
  default = ""
}
