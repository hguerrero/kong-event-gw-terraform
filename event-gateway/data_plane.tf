# ============================================================================
# Data Plane Certificate Management
# ============================================================================
# Automatically generates TLS credentials for the Event Gateway data plane,
# registers them with Konnect, and writes them to disk so docker compose can
# use them without any manual openssl steps.

# Generate RSA private key
# Equivalent to: openssl req -new -x509 -nodes -newkey rsa:2048 ...
resource "tls_private_key" "data_plane" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Generate self-signed certificate
# Equivalent to: -subj "/CN=event-gateway/C=US" -out tls.crt -keyout key.crt
resource "tls_self_signed_cert" "data_plane" {
  private_key_pem = tls_private_key.data_plane.private_key_pem

  subject {
    common_name = "event-gateway"
    country     = "US"
  }

  validity_period_hours = 8760 # 1 year

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

# Write certificate to config/certs/tls.crt (consumed by docker compose)
resource "local_file" "data_plane_cert" {
  content         = tls_self_signed_cert.data_plane.cert_pem
  filename        = "${path.module}/../config/certs/tls.crt"
  file_permission = "0644"
}

# Write private key to config/certs/key.crt (consumed by docker compose)
resource "local_file" "data_plane_key" {
  content         = tls_private_key.data_plane.private_key_pem
  filename        = "${path.module}/../config/certs/key.crt"
  file_permission = "0600"
}

# Register the certificate with the Event Gateway in Konnect
resource "konnect_event_gateway_data_plane_certificate" "data_plane_cert" {
  certificate = tls_self_signed_cert.data_plane.cert_pem
  gateway_id  = konnect_event_gateway.event_gateway_terraform.id
  name        = "Data Plane Certificate"

  depends_on = [konnect_event_gateway.event_gateway_terraform]
}
