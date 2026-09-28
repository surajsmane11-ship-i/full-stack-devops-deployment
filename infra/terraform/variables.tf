variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "project_name" {
  type    = string
  default = "devops-assessment"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "ssh_ingress_cidr" {
  description = "Your public IP in CIDR (recommended). Example: 49.37.12.34/32. For testing you can keep 0.0.0.0/0."
  type        = string
  default     = "0.0.0.0/0"
}

variable "enable_eip" {
  description = "Whether to allocate and associate an Elastic IP for the EC2 instance."
  type        = bool
  default     = true
}
