# GitHub Self-Hosted Runners on AWS (Spot Instances)

Infraestructura como código para desplegar runners self-hosted de GitHub
Actions sobre instancias EC2 **spot**, usando el módulo oficial
[`terraform-aws-github-runner`](https://github-aws-runners.github.io/terraform-aws-github-runner/).

## Para qué sirve

GitHub Actions no trae una forma nativa de escalar runners self-hosted
según demanda. Este proyecto resuelve eso: cuando se dispara un workflow
en un repo autorizado, se levanta automáticamente una instancia EC2 spot
que ejecuta el job y se destruye al terminar (runner **efímero**) — sin
mantener nada corriendo 24/7 y con el ahorro de costo de spot frente a
on-demand.

## Estructura del repo

```
bootstrap/   # Prerrequisitos: bucket S3 para el código de las Lambdas,
             # key pair EC2 y los secretos de la GitHub App en SSM.
runner/      # VPC/subnet propias + el módulo terraform-aws-github-runner
             # que crea el webhook, el autoescalador y las instancias EC2.
```

`bootstrap/` y `runner/` son dos stacks de Terraform independientes (state
separado). `runner/` ubica lo que creó `bootstrap/` buscando por nombre
(mismo `env_prefix` en ambos), no por referencia directa de Terraform.

## Qué se desplegó y en qué orden

### 1. `bootstrap/` — prerrequisitos

```bash
cd bootstrap
./deploy.sh -i <github_app_id> -k ~/keys/mi-github-app.pem -r us-east-1
```

Crea:
- **Bucket S3** (`bucket-lambda-source-<env_prefix>`) donde se publica el
  código de las Lambdas.
- **Key pair EC2** (`tls_private_key` + `aws_key_pair`), por si hace
  falta entrar por SSH a una instancia runner.
- **Secretos en SSM Parameter Store** (cifrados): `github_app_id`,
  `github_app_key_base64` (la private key `.pem` de la GitHub App, en
  base64) y `webhook_secret` (generado con `random_password`, se usa
  para validar la firma de los webhooks de GitHub).

`region`/`profile`/`env_prefix` se pasan como parámetros al script en vez
de estar hardcodeados en el `.tf`, para poder reusar el mismo código
contra distintas cuentas/entornos.

### 2. `bootstrap/publish-github-runner-lambdas.sh` — código de las Lambdas

```bash
./publish-github-runner-lambdas.sh <bucket_creado_en_el_paso_1> --tag v7.10.1
```

Descarga los `.zip` (`webhook.zip`, `runners.zip`,
`runner-binaries-syncer.zip`) del release del módulo en GitHub y los sube
al bucket S3 del paso 1, en la ruta `github-runner/<version>/`.

### 3. `runner/` — la infraestructura de los runners

```bash
cd ../runner
terraform init
terraform apply
```

Crea:
- **Red propia**: VPC + subnet pública + Internet Gateway + tabla de
  rutas, para que el proyecto sea autocontenido (no depende de una VPC
  creada a mano).
- **Módulo `github_runner`** (`github-aws-runners/github-runner/aws`),
  que arma:
  - **Webhook**: API Gateway + Lambda que recibe los eventos de GitHub.
  - **Autoescalador**: Lambda que lee la cola de jobs y lanza instancias
    EC2 spot cuando hace falta.
  - **Runners efímeros**: cada job = una instancia EC2 nueva, destruida
    al terminar el job.
  - Lee las credenciales de la GitHub App directamente desde los
    parámetros SSM creados en `bootstrap/` (nunca quedan en texto plano
    en el plan/state de este stack).
  - Restringido a los repos listados en `repository_white_list`
    (`runner/variables.tf`) y a runners con la label `practice`
    (`runner_extra_labels`).
- **Output `webhook_endpoint`**: la URL que hay que registrar como
  webhook en la GitHub App.

### 4. Configuración manual en GitHub (fuera de Terraform)

En la [GitHub App](https://github.com/settings/apps):
1. **Webhook URL** → el valor de `terraform output webhook_endpoint`.
2. **Webhook secret** → el valor guardado en el parámetro SSM
   `webhook_secret` (creado en el paso 1).
3. **Permisos** → habilitar el evento `Workflow job`.
4. **Install App** → instalarla en la cuenta/organización dueña del repo
   de prueba.

### 5. Repo de prueba y workflow

Repo [`juaca2004/Self-host-test`](https://github.com/juaca2004/Self-host-test),
agregado a `repository_white_list`, con un workflow de humo en
`.github/workflows/test-self-hosted.yml`:
- Corre en `runs-on: [self-hosted, practice]`.
- Imprime hostname/OS/usuario y consulta el metadata service de EC2
  (instance id + lifecycle) para confirmar que efectivamente corrió
  sobre una instancia spot levantada por el autoescalador.

**Resultado**: al hacer push al repo de prueba, el job quedó en cola,
el webhook lo recibió, el autoescalador levantó una instancia EC2 spot,
el runner efímero se registró, ejecutó el job y se destruyó solo al
terminar. Pipeline verificado de punta a punta.

## Requisitos para volver a desplegar esto

- Terraform, AWS CLI configurado (`aws configure`) y `curl`.
- Una GitHub App creada a mano en GitHub, con su `.pem` descargado.
- Ejecutar los pasos 1 a 5 en orden; `env_prefix` debe ser el mismo en
  `bootstrap/` y `runner/` para que este último encuentre los recursos
  del primero.

## Limpieza

Para destruir todo (evitar costos):
```bash
cd runner && terraform destroy
cd ../bootstrap && ./deploy.sh -d -i <github_app_id> -k ~/keys/mi-github-app.pem
```
