# Debe ser el MISMO env_prefix usado al aplicar bootstrap/, ya que este
# stack ubica el bucket S3, el key pair y los parámetros SSM por nombre
# (no hay estado compartido entre bootstrap/ y runner/).
variable "env_prefix" {
  description = "Environment prefix (debe coincidir con el usado en bootstrap/)"
  type        = string
  default     = "demo"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

# Profile de la AWS CLI. Vacío = usar la cadena de credenciales por defecto.
variable "aws_profile" {
  description = "AWS CLI profile"
  type        = string
  default     = ""
}

# Prefijo S3 donde publish-github-runner-lambdas.sh subió webhook.zip,
# runners.zip y runner-binaries-syncer.zip (su --prefix, default
# "github-runner/<tag-sin-v>").
variable "lambda_s3_prefix" {
  description = "Prefijo S3 de los .zip de las Lambdas"
  type        = string
  default     = "github-runner/7.10.1"
}

# Rango de la VPC creada en este stack para las instancias EC2 de los
# runners (ver aws_vpc.runner en main.tf).
variable "vpc_cidr" {
  description = "CIDR block de la VPC de los runners"
  type        = string
  default     = "10.0.0.0/16"
}

# Rango de la subnet pública dentro de esa VPC (ver aws_subnet.runner).
variable "subnet_cidr" {
  description = "CIDR block de la subnet de los runners"
  type        = string
  default     = "10.0.1.0/24"
}

# Solo estos repos (owner/repo) podrán registrar jobs contra estos runners.
variable "repository_white_list" {
  description = "Repos de GitHub (owner/repo) autorizados a usar estos runners"
  type        = list(string)
  default     = ["juaca2004/Self-host-test"]
}

# "spot" para aprovechar instancias spot (más barato, puede interrumpirse)
# u "on-demand" si prefieres estabilidad sobre costo.
variable "instance_target_capacity_type" {
  description = "Tipo de capacidad EC2 para los runners: spot | on-demand"
  type        = string
  default     = "spot"
}

# Lista de tipos de instancia candidatos; el módulo intenta en orden hasta
# encontrar capacidad disponible.
variable "runner_instance_types" {
  description = "Tipos de instancia EC2 candidatos para los runners"
  type        = list(string)
  default     = ["t3.medium"]
}

# Labels adicionales para poder apuntar workflows a estos runners con
# `runs-on: [self-hosted, <label>]`.
variable "runner_extra_labels" {
  description = "Labels extra asignadas a los runners en GitHub Actions"
  type        = list(string)
  default     = ["practice"]
}
