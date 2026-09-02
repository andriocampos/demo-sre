# =============================================================================
# OUTPUTS — Usados pelo workflow para conectar Ansible e exibir resumo
# =============================================================================

output "instance_public_ip" {
  description = "IP público da instância EC2"
  value       = aws_instance.demo.public_ip
}

output "private_key_pem" {
  description = "Chave privada SSH para Ansible (sensível)"
  value       = tls_private_key.demo.private_key_pem
  sensitive   = true
}

output "instance_id" {
  description = "ID da instância EC2"
  value       = aws_instance.demo.id
}

output "vpc_id" {
  description = "ID da VPC criada"
  value       = aws_vpc.this.id
}

output "instance_type" {
  description = "Tipo da instância"
  value       = var.instance_type
}

output "ami_id" {
  description = "AMI usada"
  value       = data.aws_ami.ubuntu.id
}
