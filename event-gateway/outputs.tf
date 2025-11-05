# ============================================================================
# Kong Identity Outputs
# ============================================================================

output "auth_server_id" {
  description = "The ID of the Kong Identity auth server"
  value       = konnect_auth_server.kafka_auth_server.id
}

output "auth_server_issuer_url" {
  description = "The issuer URL of the auth server"
  value       = konnect_auth_server.kafka_auth_server.issuer
}

output "scope_id" {
  description = "The ID of the Kafka scope"
  value       = konnect_auth_server_scopes.kafka_scope.id
}

output "client_id_1" {
  description = "The client ID for authentication"
  value       = konnect_auth_server_clients.kafka_client_1.id
}

output "client_secret_1" {
  description = "The client secret for authentication"
  value       = konnect_auth_server_clients.kafka_client_1.client_secret
  sensitive   = true
}

output "client_id_2" {
  description = "The client ID for authentication"
  value       = konnect_auth_server_clients.kafka_client_2.id
}

output "client_secret_2" {
  description = "The client secret for authentication"
  value       = konnect_auth_server_clients.kafka_client_2.client_secret
  sensitive   = true
}

# ============================================================================
# Event Gateway Outputs
# ============================================================================

output "event_gateway_id" {
  description = "The ID of the Event Gateway"
  value       = konnect_event_gateway.event_gateway_terraform.id
}

output "event_gateway_name" {
  description = "The name of the Event Gateway"
  value       = konnect_event_gateway.event_gateway_terraform.name
}

# ============================================================================
# Helper Outputs
# ============================================================================

output "token_endpoint" {
  description = "The endpoint to generate access tokens"
  value       = "${konnect_auth_server.kafka_auth_server.issuer}/oauth/token"
}

output "jwks_endpoint" {
  description = "The endpoint to fetch JWKS"
  value       = "${konnect_auth_server.kafka_auth_server.issuer}/.well-known/jwks"
}

# output "token_generation_command" {
#   description = "Command to generate an access token"
#   value       = <<-EOT
#     curl -X POST "${konnect_auth_server.kafka_auth_server.issuer}/oauth/token" \
#       -H "Content-Type: application/x-www-form-urlencoded" \
#       -d "grant_type=client_credentials" \
#       -d "client_id=${konnect_auth_server_clients.kafka_client.id}" \
#       -d "client_secret=${konnect_auth_server_clients.kafka_client.client_secret}" \
#       -d "scope=${var.scope_name}"
#   EOT
#   sensitive   = true
# }
