variable "region" {
  description = "AWS region to deploy the gateway in. Pick one close to you (latency) or close to the vendor."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Name prefix for all created resources."
  type        = string
  default     = "exitramp"
}

variable "instance_type" {
  description = "EC2 instance type. t4g.nano (arm64) is plenty for a WireGuard gateway."
  type        = string
  default     = "t4g.nano"
}

variable "ami_architecture" {
  description = "AMI architecture. Must match the instance type: arm64 for t4g.*, amd64 for t3.*/t2.*."
  type        = string
  default     = "arm64"

  validation {
    condition     = contains(["arm64", "amd64"], var.ami_architecture)
    error_message = "ami_architecture must be arm64 or amd64."
  }
}

variable "ssh_public_key" {
  description = "Your SSH public key (contents of ~/.ssh/id_ed25519.pub) for admin access."
  type        = string
}

variable "admin_cidr" {
  description = "CIDR allowed to SSH to the gateway, e.g. your current IP as 203.0.113.7/32. Yes, your IP is dynamic — that's the whole point of this project — so update this (terraform apply) when it changes, or set a broader range you trust."
  type        = string
}

variable "wireguard_port" {
  description = "UDP port WireGuard listens on."
  type        = number
  default     = 51820
}
