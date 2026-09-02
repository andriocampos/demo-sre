# =============================================================================
# SECURITY GROUP — Libera HTTP (80) e SSH (22)
# =============================================================================

resource "aws_security_group" "demo" {
  name        = "sre-demo-allow-http-ssh"
  description = "Permite HTTP e SSH para a demo SRE"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "sre-demo-allow-http-ssh"
    Environment = var.environment
  }
}

# =============================================================================
# KEY PAIR — Gerado dinamicamente (chave privada no output para Ansible)
# =============================================================================

resource "tls_private_key" "demo" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "demo" {
  key_name_prefix = "sre-demo-"
  public_key      = tls_private_key.demo.public_key_openssh

  tags = {
    Name        = "sre-demo-key"
    Environment = var.environment
  }
}

# =============================================================================
# AMI — Ubuntu 22.04 LTS (última versão disponível)
# =============================================================================

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# =============================================================================
# EC2 INSTANCE
# =============================================================================

resource "aws_instance" "demo" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.demo.id]
  key_name               = aws_key_pair.demo.key_name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name        = "ec2-${var.environment}"
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  # Aguarda a instância estar acessível via SSH
  provisioner "remote-exec" {
    inline = ["echo 'SSH ready'"]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.demo.private_key_pem
      host        = self.public_ip
      timeout     = "3m"
    }
  }
}
