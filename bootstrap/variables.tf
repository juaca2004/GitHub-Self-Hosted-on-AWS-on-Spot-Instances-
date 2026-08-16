# Región AWS donde se crean los recursos del bootstrap.
variable "aws_region" {
    description = "AWS region"
    type        = string
    default     = "us-east-1"
}

# Profile de la AWS CLI a usar. Si se deja vacío, el provider usa la
# cadena de credenciales por defecto (env vars, IAM role, etc.).
variable "aws_profile" {
    description = "AWS CLI profile"
    type        = string
    default     = ""
}

# Prefijo usado para nombrar todos los recursos (bucket, key pair, rutas
# de SSM), y así poder tener varios entornos (demo, prod, etc.) sin colisión.
variable "env_prefix" {
    description = "Environment prefix"
    type        = string
    default     = "demo"
}

# ID de la GitHub App, visible en la página de configuración de la App
# dentro de GitHub (Settings > Developer settings > GitHub Apps).
variable "github_app_id" {
    description = "GitHub App ID (from the GitHub App settings page)"
    type        = string
}

# Private key (.pem) que GitHub genera al crear la GitHub App, codificada
# en base64. Se usa junto con github_app_id para autenticar las Lambdas
# como esa App frente a la API de GitHub. Marcada sensitive para que
# Terraform no la imprima en logs/plan.
variable "github_app_key_base64" {
    description = "GitHub App private key (.pem), base64-encoded"
    type        = string
    sensitive   = true
}
