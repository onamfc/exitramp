# exitramp — AWS deployment
#
# Provisions: a small EC2 instance running the WireGuard egress gateway,
# with an Elastic IP (the static IP you hand to vendors for allowlisting).
#
# Usage:
#   terraform init
#   terraform apply -var 'ssh_public_key=ssh-ed25519 AAAA...' -var 'admin_cidr=YOUR.HOME.IP.HERE/32'
#
# The install script runs automatically via cloud-init. After apply, SSH in
# and run add-peer.sh (see outputs for the exact commands).

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_vpc" "default" {
  default = true
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-${var.ami_architecture}-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "gateway" {
  key_name   = "${var.name}-key"
  public_key = var.ssh_public_key
}

resource "aws_security_group" "gateway" {
  name        = var.name
  description = "exitramp gateway: WireGuard in, SSH from admin only"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "WireGuard"
    from_port   = var.wireguard_port
    to_port     = var.wireguard_port
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH (admin only)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = var.name }
}

resource "aws_instance" "gateway" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.gateway.key_name
  vpc_security_group_ids = [aws_security_group.gateway.id]

  # Run the stock install script on first boot, then drop the peer-management
  # scripts into the admin user's home so no manual scp step is needed.
  # WG_PORT is threaded through so the firewall, WireGuard, and the security
  # group all agree on the port.
  user_data = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail
    export WG_PORT=${var.wireguard_port}
    ${file("${path.module}/../../install-server.sh")}
    echo '${base64gzip(file("${path.module}/../../add-peer.sh"))}' | base64 -d | gunzip > /home/ubuntu/add-peer.sh
    echo '${base64gzip(file("${path.module}/../../remove-peer.sh"))}' | base64 -d | gunzip > /home/ubuntu/remove-peer.sh
    echo '${base64gzip(file("${path.module}/../../list-peers.sh"))}' | base64 -d | gunzip > /home/ubuntu/list-peers.sh
    chmod 0755 /home/ubuntu/add-peer.sh /home/ubuntu/remove-peer.sh /home/ubuntu/list-peers.sh
    chown ubuntu:ubuntu /home/ubuntu/add-peer.sh /home/ubuntu/remove-peer.sh /home/ubuntu/list-peers.sh
  EOT

  # user_data only matters on first boot (cloud-init runs it once per
  # instance). Ignore later drift so script updates in the repo never stop or
  # replace a live gateway; the egress IP itself lives on the EIP regardless.
  user_data_replace_on_change = false

  lifecycle {
    ignore_changes = [user_data]
  }

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }

  tags = { Name = var.name }
}

resource "aws_eip" "gateway" {
  domain = "vpc"
  tags   = { Name = var.name }
}

resource "aws_eip_association" "gateway" {
  instance_id   = aws_instance.gateway.id
  allocation_id = aws_eip.gateway.id
}
