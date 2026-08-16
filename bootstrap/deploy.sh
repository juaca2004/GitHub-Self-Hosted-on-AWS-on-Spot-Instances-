#!/usr/bin/env bash
#
# Ejecuta el bootstrap de Terraform (bucket S3, key pair, secretos en SSM)
# pasando los valores necesarios como parámetros de línea de comandos, en
# vez de tenerlos hardcodeados o en un .tfvars versionado.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Valores por defecto
AWS_REGION="us-east-1"
AWS_PROFILE=""
ENV_PREFIX="demo"
GITHUB_APP_ID=""
GITHUB_APP_KEY_FILE=""
ACTION="apply"
AUTO_APPROVE=false

usage() {
  cat <<EOF
Uso: $(basename "$0") -i <github_app_id> -k <path_al_pem> [opciones]

Requeridos:
  -i, --github-app-id <id>      ID de la GitHub App
  -k, --github-app-key <path>   Ruta al archivo .pem de la GitHub App

Opcionales:
  -r, --region <region>         Región AWS (default: ${AWS_REGION})
  -p, --profile <profile>       Profile de AWS CLI (default: credenciales por defecto)
  -e, --env-prefix <prefix>     Prefijo de entorno (default: ${ENV_PREFIX})
  -d, --destroy                 Ejecuta 'terraform destroy' en vez de 'apply'
  -y, --yes                     Auto-aprueba el apply/destroy (sin confirmación)
  -h, --help                    Muestra esta ayuda

Ejemplo:
  $(basename "$0") -i 123456 -k ~/keys/mi-github-app.pem -r us-east-1 -p mi-profile -e prod
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--github-app-id) GITHUB_APP_ID="$2"; shift 2 ;;
    -k|--github-app-key) GITHUB_APP_KEY_FILE="$2"; shift 2 ;;
    -r|--region) AWS_REGION="$2"; shift 2 ;;
    -p|--profile) AWS_PROFILE="$2"; shift 2 ;;
    -e|--env-prefix) ENV_PREFIX="$2"; shift 2 ;;
    -d|--destroy) ACTION="destroy"; shift ;;
    -y|--yes) AUTO_APPROVE=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Opción desconocida: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ "$ACTION" == "apply" ]]; then
  if [[ -z "$GITHUB_APP_ID" ]]; then
    echo "Error: falta -i/--github-app-id" >&2
    exit 1
  fi
  if [[ -z "$GITHUB_APP_KEY_FILE" ]]; then
    echo "Error: falta -k/--github-app-key" >&2
    exit 1
  fi
  if [[ ! -f "$GITHUB_APP_KEY_FILE" ]]; then
    echo "Error: no existe el archivo '$GITHUB_APP_KEY_FILE'" >&2
    exit 1
  fi
  GITHUB_APP_KEY_BASE64="$(base64 -w0 "$GITHUB_APP_KEY_FILE")"
else
  # En destroy no se usan de verdad, pero son variables sin default y
  # Terraform las pediría de forma interactiva si quedan vacías.
  GITHUB_APP_ID="${GITHUB_APP_ID:-destroy}"
  GITHUB_APP_KEY_BASE64="destroy"
fi

# Archivo tfvars temporal (evita pasar el secreto por argv, visible en `ps`,
# y evita dejarlo persistido en el repo). Se borra al salir del script.
TMP_TFVARS="$(mktemp)"
chmod 600 "$TMP_TFVARS"
trap 'rm -f "$TMP_TFVARS"' EXIT

{
  echo "aws_region             = \"${AWS_REGION}\""
  echo "aws_profile            = \"${AWS_PROFILE}\""
  echo "env_prefix             = \"${ENV_PREFIX}\""
  echo "github_app_id          = \"${GITHUB_APP_ID}\""
  echo "github_app_key_base64  = \"${GITHUB_APP_KEY_BASE64}\""
} > "$TMP_TFVARS"

cd "$SCRIPT_DIR"
terraform init -input=false

TF_ARGS=(-var-file="$TMP_TFVARS")
if [[ "$AUTO_APPROVE" == true ]]; then
  TF_ARGS+=(-auto-approve)
fi

if [[ "$ACTION" == "destroy" ]]; then
  terraform destroy "${TF_ARGS[@]}"
else
  terraform apply "${TF_ARGS[@]}"
fi
