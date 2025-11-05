# ============================================================================
# Konnect Configuration
# ============================================================================

variable "konnect_server_url" {
  type        = string
  description = "Which Konnect instance to point at"
  default     = "https://us.api.konghq.tech"
}

variable "konnect_token" {
  type        = string
  description = "API token to reach Konnect"
  sensitive   = true
}

# ============================================================================
# Kong Identity Configuration
# ============================================================================

variable "auth_server_name" {
  type        = string
  description = "Name of the Kong Identity auth server"
  default     = "Appointments Dev"
}

variable "auth_server_audience" {
  type        = string
  description = "Audience for the auth server"
  default     = "http://myhttpbin.dev"
}

variable "auth_server_description" {
  type        = string
  description = "Description of the auth server"
  default     = "Auth server for the Appointment dev environment"
}

variable "scope_name" {
  type        = string
  description = "Name of the scope for Kafka authentication"
  default     = "kafka"
}

variable "scope_description" {
  type        = string
  description = "Description of the scope"
  default     = "Scope to test Kong Identity"
}

variable "client_name_1" {
  type        = string
  description = "Name of the client for machine-to-machine authentication"
  default     = "Client1"
}

variable "client_name_2" {
  type        = string
  description = "Name of the client for machine-to-machine authentication"
  default     = "Client2"
}

variable "access_token_duration" {
  type        = number
  description = "Access token duration in seconds"
  default     = 3600
}

variable "id_token_duration" {
  type        = number
  description = "ID token duration in seconds"
  default     = 3600
}

# ============================================================================
# Event Gateway Configuration
# ============================================================================

variable "event_gateway_name" {
  type        = string
  description = "Name of the Event Gateway instance"
  default     = "event_gateway_terraform"
}

variable "backend_cluster_bootstrap_servers" {
  description = "List of bootstrap servers"
  type        = list(string)
  default     = [ 
    "kafka1:9092", 
    "kafka2:9092", 
    "kafka3:9092" 
]
}