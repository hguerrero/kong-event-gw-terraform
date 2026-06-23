terraform {
  required_version = ">= 1.0"

  required_providers {
    konnect = {
      source  = "Kong/konnect"
      version = "3.18.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

# ============================================================================
# Kong Identity Resources
# ============================================================================

# Auth Server
resource "konnect_identity_auth_server" "kafka_auth_server" {
  provider    = konnect
  name        = var.auth_server_name
  audience    = var.auth_server_audience
  description = var.auth_server_description
}

# Scope for Kafka authentication
resource "konnect_identity_auth_server_scope" "kafka_scope" {
  provider            = konnect
  auth_server_id      = konnect_identity_auth_server.kafka_auth_server.id
  name                = var.scope_name
  description         = var.scope_description
  default             = false
  include_in_metadata = false
  enabled             = true

  depends_on = [konnect_identity_auth_server.kafka_auth_server]
}

# Client 1 for machine-to-machine authentication
resource "konnect_identity_auth_server_client" "kafka_client_1" {
  provider              = konnect
  auth_server_id        = konnect_identity_auth_server.kafka_auth_server.id
  name                  = var.client_name_1
  grant_types           = ["client_credentials"]
  allow_all_scopes      = false
  allow_scopes          = [konnect_identity_auth_server_scope.kafka_scope.id]
  access_token_duration = var.access_token_duration
  id_token_duration     = var.id_token_duration
  response_types        = ["id_token", "token"]

  depends_on = [konnect_identity_auth_server.kafka_auth_server]
}

# Client 2 for machine-to-machine authentication
resource "konnect_identity_auth_server_client" "kafka_client_2" {
  provider              = konnect
  auth_server_id        = konnect_identity_auth_server.kafka_auth_server.id
  name                  = var.client_name_2
  grant_types           = ["client_credentials"]
  allow_all_scopes      = false
  allow_scopes          = [konnect_identity_auth_server_scope.kafka_scope.id]
  access_token_duration = var.access_token_duration
  id_token_duration     = var.id_token_duration
  response_types        = ["id_token", "token"]

  depends_on = [konnect_identity_auth_server.kafka_auth_server]
}

# ============================================================================
# Event Gateway Resource
# ============================================================================

# Event Gateway - configured with Kong Identity
resource "konnect_event_gateway" "event_gateway_terraform" {
  provider    = konnect
  name        = var.event_gateway_name
  description = var.event_gateway_description

  # This ensures the Event Gateway is created after Kong Identity is set up
  depends_on = [
    konnect_identity_auth_server.kafka_auth_server,
    konnect_identity_auth_server_scope.kafka_scope
  ]
}

resource "konnect_event_gateway_backend_cluster" "backend_cluster" {
  provider    = konnect
  name        = "local-backend-cluster"
  description = "local cluster"
  gateway_id  = konnect_event_gateway.event_gateway_terraform.id

  authentication = {
    anonymous = {}
  }

  bootstrap_servers = var.backend_cluster_bootstrap_servers

  tls = {
    enabled = false
  }

  insecure_allow_anonymous_virtual_cluster_auth = true

  depends_on = [konnect_event_gateway.event_gateway_terraform]
}

resource "konnect_event_gateway_virtual_cluster" "virtual_cluster" {
  provider    = konnect
  name        = "virtual-cluster"
  description = "team virtual cluster"
  gateway_id  = konnect_event_gateway.event_gateway_terraform.id

  destination = {
    id = konnect_event_gateway_backend_cluster.backend_cluster.id
  }

  acl_mode  = "enforce_on_gateway"
  dns_label = "vcluster"

  namespace = {
    prefix = "internal-"
    mode   = "hide_prefix"
    additional = {
      consumer_groups = [{}]
      topics = [{
        exact_list = {
          conflict = "warn"
          exact_list = [{
            backend = "nw.ops.test.hello-world.v1"
            }, {
            backend = "infosec.security.fraud.risk-scores.v3"
            }, {
            backend = "nw.ledger.transactions.high-value-wire-transfers.v1"
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
          endpoint = "${konnect_identity_auth_server.kafka_auth_server.issuer}/.well-known/jwks"
          timeout  = "1s"
        }
      }
    }
  ]

  depends_on = [konnect_event_gateway.event_gateway_terraform, konnect_event_gateway_backend_cluster.backend_cluster]
}

resource "konnect_event_gateway_listener" "listener" {
  provider    = konnect
  name        = "localhost-listener"
  description = "localhost listener"
  gateway_id  = konnect_event_gateway.event_gateway_terraform.id

  addresses = ["0.0.0.0"]
  ports     = ["19092-19192"]

  depends_on = [konnect_event_gateway.event_gateway_terraform]
}

resource "konnect_event_gateway_listener_policy_forward_to_virtual_cluster" "forward_to_vcluster" {
  provider    = konnect
  name        = "forward-to-vcluster"
  description = "forward to vcluster policy"
  gateway_id  = konnect_event_gateway.event_gateway_terraform.id
  listener_id = konnect_event_gateway_listener.listener.id

  config = {
    port_mapping = {
      advertised_host = "host.docker.internal"
      bootstrap_port  = "none"
      destination = {
        id = konnect_event_gateway_virtual_cluster.virtual_cluster.id
      }
    }
  }

  depends_on = [konnect_event_gateway.event_gateway_terraform, konnect_event_gateway_virtual_cluster.virtual_cluster]
}

// Add ACL policy for user1
resource "konnect_event_gateway_cluster_policy_acls" "acl_topic_policy_u1" {
  provider           = konnect
  name               = "acl_topic_policy1"
  description        = "ACL policy for ensuring access to topics based on principals"
  gateway_id         = konnect_event_gateway.event_gateway_terraform.id
  virtual_cluster_id = konnect_event_gateway_virtual_cluster.virtual_cluster.id

  condition = "context.auth.principal.name == '${konnect_identity_auth_server_client.kafka_client_1.id}' || context.auth.principal.name == 'user1'"
  config = {
    rules = [
      {
        action = "allow"
        operations = [
          { name = "describe" },
          { name = "create" },
          { name = "read" },
          { name = "write" }
        ]
        resource_type = "topic"
        resource_names = [{
          match = "*"
        }]
      },
      {
        action = "allow"
        operations = [
          { name = "read" },
          { name = "describe_configs" }
        ]
        resource_type = "group"
        resource_names = [
          { match = "*" }
        ]
      }
    ]
  }
}

// Add ACL policy for user2
resource "konnect_event_gateway_cluster_policy_acls" "acl_topic_policy_u2" {
  provider           = konnect
  name               = "acl_topic_policy2"
  description        = "ACL policy for ensuring access to topics based on principals"
  gateway_id         = konnect_event_gateway.event_gateway_terraform.id
  virtual_cluster_id = konnect_event_gateway_virtual_cluster.virtual_cluster.id

  condition = "context.auth.principal.name == '${konnect_identity_auth_server_client.kafka_client_2.id}' || context.auth.principal.name == 'user2'"
  config = {
    rules = [
      {
        action = "allow"
        operations = [
          { name = "describe" }
        ]
        resource_type = "topic"
        resource_names = [{
          match = "nw.ops.test.hello-world.v1"
          }, {
          match = "infosec.security.fraud.risk-scores.v3"
          }, {
          match = "nw.ledger.transactions.high-value-wire-transfers.v1"
        }]
      },
      {
        action = "allow"
        operations = [
          { name = "read" }
        ]
        resource_type = "topic"
        resource_names = [{
          match = "nw.ops.test.hello-world.v1"
        }]
      },
      {
        action = "allow"
        operations = [
          { name = "read" },
          { name = "describe_configs" }
        ]
        resource_type = "group"
        resource_names = [
          { match = "*" }
        ]
      }
    ]
  }
}

// Add skip record policy on orders topic based on header & principal
resource "konnect_event_gateway_consume_policy_skip_record" "skip_record" {
  provider           = konnect
  name               = "skip_records"
  description        = "skip records"
  gateway_id         = konnect_event_gateway.event_gateway_terraform.id
  virtual_cluster_id = konnect_event_gateway_virtual_cluster.virtual_cluster.id

  condition = "record.headers['internal'] == 'true' && context.auth.principal.name != '${konnect_identity_auth_server_client.kafka_client_1.id}' && context.auth.principal.name != 'user1'"
}
