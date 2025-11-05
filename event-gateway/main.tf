terraform {
  required_version = ">= 1.0"

  required_providers {
    konnect-beta = {
      source  = "Kong/konnect-beta"
      version = "~> 0.11.1"
    }
  }
}

# ============================================================================
# Kong Identity Resources
# ============================================================================

# Auth Server
resource "konnect_auth_server" "kafka_auth_server" {
  provider    = konnect-beta
  name        = var.auth_server_name
  audience    = var.auth_server_audience
  description = var.auth_server_description
}

# Scope for Kafka authentication
resource "konnect_auth_server_scopes" "kafka_scope" {
  provider            = konnect-beta
  auth_server_id      = konnect_auth_server.kafka_auth_server.id
  name                = var.scope_name
  description         = var.scope_description
  default             = false
  include_in_metadata = false
  enabled             = true

  depends_on = [konnect_auth_server.kafka_auth_server]
}

# Client 1 for machine-to-machine authentication
resource "konnect_auth_server_clients" "kafka_client_1" {
  provider              = konnect-beta
  auth_server_id        = konnect_auth_server.kafka_auth_server.id
  name                  = var.client_name_1
  grant_types           = ["client_credentials"]
  allow_all_scopes      = false
  allow_scopes          = [konnect_auth_server_scopes.kafka_scope.id]
  access_token_duration = var.access_token_duration
  id_token_duration     = var.id_token_duration
  response_types        = ["id_token", "token"]

  depends_on = [konnect_auth_server.kafka_auth_server]
}

# Client 2 for machine-to-machine authentication
resource "konnect_auth_server_clients" "kafka_client_2" {
  provider              = konnect-beta
  auth_server_id        = konnect_auth_server.kafka_auth_server.id
  name                  = var.client_name_2
  grant_types           = ["client_credentials"]
  allow_all_scopes      = false
  allow_scopes          = [konnect_auth_server_scopes.kafka_scope.id]
  access_token_duration = var.access_token_duration
  id_token_duration     = var.id_token_duration
  response_types        = ["id_token", "token"]

  depends_on = [konnect_auth_server.kafka_auth_server]
}

# ============================================================================
# Event Gateway Resource
# ============================================================================

# Event Gateway - configured with Kong Identity
resource "konnect_event_gateway" "event_gateway_terraform" {
  provider = konnect-beta
  name     = var.event_gateway_name

  # This ensures the Event Gateway is created after Kong Identity is set up
  depends_on = [
    konnect_auth_server.kafka_auth_server,
    konnect_auth_server_scopes.kafka_scope
  ]
}

resource "konnect_event_gateway_backend_cluster" "backend_cluster" {
  provider    = konnect-beta
  name        = "confluent-backend-cluster"
  description = "confluent cloud cluster"
  gateway_id  = konnect_event_gateway.event_gateway_terraform.id

  authentication = {
    sasl_plain = {
      username = "$${env['KAFKA_USERNAME']}"
      password = "$${env['KAFKA_PASSWORD']}"
    }
  }

  bootstrap_servers = var.backend_cluster_bootstrap_servers

  tls = {
    enabled = true
  }

  insecure_allow_anonymous_virtual_cluster_auth = true

  depends_on = [konnect_event_gateway.event_gateway_terraform]
}

resource "konnect_event_gateway_virtual_cluster" "virtual_cluster" {
  provider    = konnect-beta
  name        = "virtual-cluster"
  description = "team virtual cluster"
  gateway_id  = konnect_event_gateway.event_gateway_terraform.id

  destination = {
    id = konnect_event_gateway_backend_cluster.backend_cluster.id
  }

  acl_mode = "enforce_on_gateway"
  dns_label = "vcluster"

  namespace = {
    prefix = "my-"
    mode   = "hide_prefix"
    additional = {
      consumer_groups = [{}]
      topics = [{
        exact_list = {
          conflict = "warn"
          exact_list = [{
            backend = "extra_topic"
          }]
        }
      }]
    }
  }

  authentication = [
    {
      oauth_bearer = {
        mediation = "terminate"
        jwks = {
          endpoint = "${konnect_auth_server.kafka_auth_server.issuer}/.well-known/jwks"
          timeout  = "1s"
        }
      }
    }
  ]

  depends_on = [konnect_event_gateway.event_gateway_terraform, konnect_event_gateway_backend_cluster.backend_cluster]
}

resource "konnect_event_gateway_listener" "listener" {
  provider    = konnect-beta
  name        = "localhost-listener"
  description = "localhost listener"
  gateway_id  = konnect_event_gateway.event_gateway_terraform.id

  addresses = ["0.0.0.0"]
  ports     = ["19092-19192"]

  depends_on = [konnect_event_gateway.event_gateway_terraform]
}

resource "konnect_event_gateway_listener_policy_forward_to_virtual_cluster" "forward_to_vcluster" {
  provider                  = konnect-beta
  name                      = "forward-to-vcluster"
  description               = "forward to vcluster policy"
  gateway_id                = konnect_event_gateway.event_gateway_terraform.id
  event_gateway_listener_id = konnect_event_gateway_listener.listener.id

  config = {
    port_mapping = {
      advertised_host = "localhost"
      destination = {
        virtual_cluster_reference_by_id = {
          id = konnect_event_gateway_virtual_cluster.virtual_cluster.id
        }
      }
    }
  }

  depends_on = [konnect_event_gateway.event_gateway_terraform, konnect_event_gateway_virtual_cluster.virtual_cluster]
}

// Add ACL policy for user1
resource "konnect_event_gateway_cluster_policy_acls" "acl_topic_policy_u1" {
  provider           = konnect-beta
  name               = "acl_topic_policy1"
  description        = "ACL policy for ensuring access to topics based on principals"
  gateway_id         = konnect_event_gateway.event_gateway_terraform.id
  virtual_cluster_id = konnect_event_gateway_virtual_cluster.virtual_cluster.id

  condition = "context.auth.principal.name == '${konnect_auth_server_clients.kafka_client_1.id}'"
  config = {
    rules = [
      {
        action = "allow"
        operations = [
          { name = "describe" },
          { name = "read" },
          { name = "write" }
        ]
        resource_type = "topic"
        resource_names = [{
          match = "*"
        }]
      }
    ]
  }
}

// Add ACL policy for user2
resource "konnect_event_gateway_cluster_policy_acls" "acl_topic_policy_u2" {
  provider           = konnect-beta
  name               = "acl_topic_policy2"
  description        = "ACL policy for ensuring access to topics based on principals"
  gateway_id         = konnect_event_gateway.event_gateway_terraform.id
  virtual_cluster_id = konnect_event_gateway_virtual_cluster.virtual_cluster.id

  condition = "context.auth.principal.name == '${konnect_auth_server_clients.kafka_client_2.id}'"
  config = {
    rules = [
      {
        action = "allow"
        operations = [
          { name = "describe" }
        ]
        resource_type = "topic"
        resource_names = [{
          match = "topic"
          }, {
          match = "topic-encrypted"
          }, {
          match = "extra_topic"
        }]
        }, {
        action = "allow"
        operations = [
          { name = "read" }
        ]
        resource_type = "topic"
        resource_names = [{
          match = "topic"
        }]
      }
    ]
  }
}

// Add skip record policy on orders topic based on header & principal
resource "konnect_event_gateway_consume_policy_skip_record" "skip_record" {
  provider           = konnect-beta
  name               = "skip_records"
  description        = "skip records"
  gateway_id         = konnect_event_gateway.event_gateway_terraform.id
  virtual_cluster_id = konnect_event_gateway_virtual_cluster.virtual_cluster.id

  condition = "record.headers['internal'] == 'true' && context.auth.principal.name != '${konnect_auth_server_clients.kafka_client_1.id}'"
}
