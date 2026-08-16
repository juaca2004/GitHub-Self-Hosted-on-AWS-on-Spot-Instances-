locals {
  # Prefijo con el que el módulo nombra todos sus recursos (Lambdas, SQS,
  # API Gateway, etc.). Incluye env_prefix para no chocar con otros entornos.
  runner_prefix = "gh-runner-${var.env_prefix}"
}

# --- Red donde se lanzan las instancias EC2 de los runners ---
# Se crea acá en vez de reutilizar una VPC existente para que el proyecto
# sea autocontenido: `terraform apply` en runner/ deja todo listo sin
# depender de infraestructura de red creada a mano.

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "runner" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.runner_prefix}-vpc"
  }
}

# Subnet pública: los runners salen a internet por IP pública propia
# (associate_public_ipv4_address = true más abajo), sin NAT Gateway.
resource "aws_subnet" "runner" {
  vpc_id                  = aws_vpc.runner.id
  cidr_block              = var.subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.runner_prefix}-subnet"
  }
}

resource "aws_internet_gateway" "runner" {
  vpc_id = aws_vpc.runner.id

  tags = {
    Name = "${local.runner_prefix}-igw"
  }
}

resource "aws_route_table" "runner" {
  vpc_id = aws_vpc.runner.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.runner.id
  }

  tags = {
    Name = "${local.runner_prefix}-rt"
  }
}

resource "aws_route_table_association" "runner" {
  subnet_id      = aws_subnet.runner.id
  route_table_id = aws_route_table.runner.id
}

# --- Recursos que creó bootstrap/, referenciados aquí SOLO por nombre ---
# bootstrap/ y runner/ son dos root modules con estado separado, así que
# no se puede hacer referencia directa a sus resources; se buscan por el
# nombre/ruta determinística que usa bootstrap/main.tf.

data "aws_s3_bucket" "lambda_source" {
  bucket = "bucket-lambda-source-${var.env_prefix}"
}

data "aws_key_pair" "runners" {
  key_name = "github-runners-${var.env_prefix}"
}

data "aws_ssm_parameter" "github_app_id" {
  name = "/${var.env_prefix}/github-runner/github_app_id"
}

data "aws_ssm_parameter" "github_app_key_base64" {
  name = "/${var.env_prefix}/github-runner/github_app_key_base64"
}

data "aws_ssm_parameter" "github_app_webhook_secret" {
  name = "/${var.env_prefix}/github-runner/webhook_secret"
}

# --- Módulo oficial: crea el webhook, el scaler y las instancias EC2 ---

module "github_runner" {
  source = "github-aws-runners/github-runner/aws"
  # Debe coincidir con el tag usado en
  # bootstrap/publish-github-runner-lambdas.sh (--tag), ya que el código
  # de las Lambdas y los recursos de este módulo van pareados por release.
  # Terraform exige que la versión del módulo sea un literal (se resuelve
  # en `init`, antes de evaluar variables), por eso no es var.*.
  version = "7.10.1"

  aws_region = var.aws_region
  vpc_id     = aws_vpc.runner.id
  subnet_ids = [aws_subnet.runner.id]
  prefix     = local.runner_prefix

  # Credenciales de la GitHub App leídas desde SSM (creadas por bootstrap/)
  # en vez de pasarlas en texto plano: el módulo las obtiene en runtime,
  # nunca quedan como valor plano en el plan/state de este stack.
  github_app = {
    id_ssm = {
      arn  = data.aws_ssm_parameter.github_app_id.arn
      name = data.aws_ssm_parameter.github_app_id.name
    }
    key_base64_ssm = {
      arn  = data.aws_ssm_parameter.github_app_key_base64.arn
      name = data.aws_ssm_parameter.github_app_key_base64.name
    }
    webhook_secret_ssm = {
      arn  = data.aws_ssm_parameter.github_app_webhook_secret.arn
      name = data.aws_ssm_parameter.github_app_webhook_secret.name
    }
  }

  # Código de las Lambdas, publicado en el bucket de bootstrap/ mediante
  # bootstrap/publish-github-runner-lambdas.sh.
  lambda_s3_bucket      = data.aws_s3_bucket.lambda_source.id
  webhook_lambda_s3_key = "${var.lambda_s3_prefix}/webhook.zip"
  runners_lambda_s3_key = "${var.lambda_s3_prefix}/runners.zip"
  syncer_lambda_s3_key  = "${var.lambda_s3_prefix}/runner-binaries-syncer.zip"

  # Descarga el binario del runner a S3 de antemano para que las
  # instancias arranquen más rápido en vez de bajarlo de GitHub en cada boot.
  enable_runner_binaries_syncer = true

  # Rol de servicio que AWS necesita para poder lanzar instancias spot.
  create_service_linked_role_spot = true

  # Runners a nivel de repositorio (no de organización) y efímeros: cada
  # job levanta una instancia nueva que se destruye al terminar, sin
  # estado residual entre jobs.
  enable_organization_runners = false
  enable_ephemeral_runners    = true
  delay_webhook_event         = 0

  # -1 = sin límite de concurrencia en la Lambda que escala hacia arriba.
  scale_up_reserved_concurrent_executions = -1

  instance_target_capacity_type = var.instance_target_capacity_type
  instance_types                = var.runner_instance_types

  block_device_mappings = [{
    device_name = "/dev/sda1"
    volume_size = 20
  }]

  # IP pública para que la instancia pueda salir a internet (descargar el
  # binario del runner, hablar con la API de GitHub) sin depender de un
  # NAT Gateway.
  associate_public_ipv4_address = true

  repository_white_list = var.repository_white_list
  runner_extra_labels   = var.runner_extra_labels

  # Key pair generado en bootstrap/, por si hace falta entrar por SSH a
  # depurar una instancia.
  key_name = data.aws_key_pair.runners.key_name

  # Permite conectarse a las instancias vía AWS Systems Manager Session
  # Manager, sin necesidad de abrir el puerto 22.
  enable_ssm_on_runners = true

  # Dependencia explícita: aunque vpc_id/subnet_ids ya generan una
  # dependencia implícita, se deja explícita para garantizar que la red
  # (VPC, subnet, IGW y su ruta a internet) esté completamente creada
  # antes de que el módulo lance instancias EC2 o recursos que viven
  # dentro de esa subnet.
  depends_on = [
    aws_vpc.runner,
    aws_subnet.runner,
    aws_route_table_association.runner,
  ]
}
