variable "aws_region" {
  description = "Região AWS"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Nome do ambiente"
  type        = string
  default     = "sre-demo"
}

variable "vpc_cidr" {
  description = "CIDR da VPC"
  type        = string
  default     = "10.70.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR da subnet pública"
  type        = string
  default     = "10.70.1.0/24"
}

variable "instance_type" {
  description = "Tipo da instância EC2"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "Nome do key pair gerado"
  type        = string
  default     = "sre-demo-key"
}
