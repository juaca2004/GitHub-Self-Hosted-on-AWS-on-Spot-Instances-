# Bucket S3 donde se publica el código (.zip) de las Lambdas del módulo
# terraform-aws-github-runner (webhook, scaler, agent-sync, etc.). El módulo
# principal referencia este bucket para leer/subir los artefactos versionados.
module "s3_bucket" {
  source = "terraform-aws-modules/s3-bucket/aws"

  bucket = "bucket-lambda-source-${var.env_prefix}"
  version = "5.10.0"

  control_object_ownership = true
  object_ownership         = "BucketOwnerEnforced"

  versioning = {
    enabled = true
  }

  attach_deny_insecure_transport_policy = true

  force_destroy = false


  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Data source con el account ID de la cuenta AWS actual. Disponible para
# usarse en policies o ARNs de recursos que lo requieran (ej. condiciones
# de bucket policy o KMS key policy).
data "aws_caller_identity" "current" {}

# Genera un par de llaves RSA para el acceso SSH a las instancias EC2 de
# los runners (útil para depurar). La llave pública se registra en AWS
# como aws_key_pair; la privada solo queda en el state de Terraform.
resource "tls_private_key" "runners" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Registra en AWS la llave pública generada arriba, para poder asociarla
# a las instancias EC2 de los runners vía su `key_name`.
resource "aws_key_pair" "runners" {
  key_name   = "github-runners-${var.env_prefix}"
  public_key = tls_private_key.runners.public_key_openssh
}

# Secreto aleatorio compartido con GitHub al configurar el webhook. Las
# Lambdas lo usan para validar la firma HMAC de cada evento entrante y
# así descartar peticiones que no vienen realmente de GitHub.
resource "random_password" "github_app_webhook_secret" {
  length  = 32
  special = false
}

# Guarda el webhook secret en SSM Parameter Store (cifrado) para que el
# módulo principal lo lea al desplegar la Lambda del webhook.
resource "aws_ssm_parameter" "github_app_webhook_secret" {
  name  = "/${var.env_prefix}/github-runner/webhook_secret"
  type  = "SecureString"
  value = random_password.github_app_webhook_secret.result
}

# Guarda el ID de la GitHub App (asignado por GitHub al crearla) en SSM,
# para que el módulo principal lo use al autenticarse contra la API de
# GitHub como esa App.
resource "aws_ssm_parameter" "github_app_id" {
  name  = "/${var.env_prefix}/github-runner/github_app_id"
  type  = "SecureString"
  value = var.github_app_id
}

# Guarda la private key (.pem, en base64) de la GitHub App en SSM. Junto
# con github_app_id, es lo que las Lambdas usan para generar los JWT/tokens
# de autenticación contra la API de GitHub.
resource "aws_ssm_parameter" "github_app_key_base64" {
  name  = "/${var.env_prefix}/github-runner/github_app_key_base64"
  type  = "SecureString"
  value = var.github_app_key_base64
}
