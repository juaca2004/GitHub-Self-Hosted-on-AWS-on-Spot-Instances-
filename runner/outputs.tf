# URL a configurar como "Webhook URL" en la página de la GitHub App.
output "webhook_endpoint" {
  description = "Endpoint del webhook a registrar en la GitHub App"
  value       = module.github_runner.webhook.endpoint
}
