# Kong Event Gateway with Kong Identity

This project demonstrates how to set up Kong Event Gateway with Kong Identity authentication using Terraform, including virtual clusters, ACL policies, and OAuth Bearer authentication.

## Architecture Overview

This setup creates a complete Kafka proxy solution with:

- **Kong Identity (Terraform-managed)**:
  - Auth server for OAuth token issuance
  - Kafka scope for authorization
  - Two OAuth clients (Client1 and Client2) with different permissions
- **Backend Cluster**: Connects to Confluent Cloud (or any Kafka cluster) using SASL_PLAIN authentication
- **Virtual Cluster**: Provides namespace isolation with prefix management (`my-` prefix)
- **Authentication**: OAuth Bearer tokens via Kong Identity
- **ACL Policies**: Fine-grained access control per OAuth client
- **Record Filtering**: Skip records based on headers and principals
- **Listener Configuration**: Local listener on ports 19092-19192

## Workflow Overview

This setup is **fully automated with Terraform**:

1. **Terraform Deployment** (Single Step)
   - Creates Kong Identity resources (auth server, scope, clients)
   - Deploys Event Gateway with backend cluster
   - Configures virtual cluster with OAuth authentication
   - Sets up ACL policies for each client
   - Configures listeners and forwarding policies

2. **Token Generation** (Post-deployment)
   - Generate OAuth tokens for Client1 and Client2
   - Use tokens to authenticate Kafka clients

## Prerequisites

- **Konnect Account**: This project requires a Konnect personal access token
- **Terraform**: Version 1.0 or higher
- **Kafka Cluster**: Access to a Kafka cluster (e.g., Confluent Cloud) with bootstrap servers and credentials

### Getting Your Konnect Token

1. Create a new personal access token by opening the Konnect PAT page and selecting Generate Token
2. Export your token to an environment variable:
   ```sh
   export KONNECT_TOKEN='YOUR_KONNECT_PAT'
   ```

## Setup Instructions

### Step 1: Deploy Everything with Terraform

Terraform will create all resources in a single deployment.

#### 1.1. Configure Terraform Variables

```sh
cd event-gateway
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

Required variables in `terraform.tfvars`:
- `konnect_token`: Your Konnect personal access token
- `backend_cluster_bootstrap_servers`: List of Kafka bootstrap servers (e.g., Confluent Cloud endpoints)

Optional variables (with defaults):
- `auth_server_name`: Name for the Kong Identity auth server (default: "Appointments Dev")
- `auth_server_audience`: Audience for the auth server (default: "http://myhttpbin.dev")
- `client_name_1`: Name for the first OAuth client (default: "Client1")
- `client_name_2`: Name for the second OAuth client (default: "Client2")
- `event_gateway_name`: Name for the Event Gateway (default: "event_gateway_terraform")

#### 1.2. Set Environment Variables

The configuration uses environment variables for backend Kafka cluster credentials:

```sh
# Backend cluster credentials (Confluent Cloud or your Kafka cluster)
export KAFKA_USERNAME='your-kafka-username'
export KAFKA_PASSWORD='your-kafka-password'
```

#### 1.3. Initialize and Apply Terraform

```sh
terraform init
terraform plan
terraform apply
```

This will create:
- **Kong Identity Resources**:
  - Auth server
  - Kafka scope
  - Two OAuth clients (Client1 and Client2)
- **Event Gateway Resources**:
  - Event Gateway instance
  - Backend cluster connection to Confluent Cloud
  - Virtual cluster with namespace configuration and OAuth authentication
  - ACL policies for Client1 (full access) and Client2 (limited access)
  - Skip record policy for filtering
  - Listener on localhost:19092-19192
  - Forwarding policy to virtual cluster

#### 1.4. View Outputs

After deployment, view the created resources:

```sh
terraform output
```

Important outputs:
- `auth_server_id`: ID of the created auth server
- `auth_server_issuer_url`: Issuer URL for token generation
- `client_id_1` / `client_id_2`: OAuth client IDs
- `client_secret_1` / `client_secret_2`: OAuth client secrets (sensitive)
- `token_endpoint`: Endpoint to generate access tokens
- `jwks_endpoint`: JWKS endpoint for token validation
- `event_gateway_id`: ID of the Event Gateway

### Step 2: Generate Access Tokens

After Terraform deployment, generate OAuth tokens for each client.

#### 2.1. Get Token Endpoint from Terraform Output

```sh
export TOKEN_ENDPOINT=$(terraform output -raw token_endpoint)
```

#### 2.2. Generate Token for Client1 (Full Access)

```sh
export CLIENT_ID_1=$(terraform output -raw client_id_1)
export CLIENT_SECRET_1=$(terraform output -raw client_secret_1)

curl -X POST "$TOKEN_ENDPOINT" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=$CLIENT_ID_1" \
  -d "client_secret=$CLIENT_SECRET_1" \
  -d "scope=kafka"
```

Export the access token:

```sh
export ACCESS_TOKEN_CLIENT1='YOUR-ACCESS-TOKEN-FROM-RESPONSE'
```

#### 2.3. Generate Token for Client2 (Limited Access)

```sh
export CLIENT_ID_2=$(terraform output -raw client_id_2)
export CLIENT_SECRET_2=$(terraform output -raw client_secret_2)

curl -X POST "$TOKEN_ENDPOINT" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=$CLIENT_ID_2" \
  -d "client_secret=$CLIENT_SECRET_2" \
  -d "scope=kafka"
```

Export the access token:

```sh
export ACCESS_TOKEN_CLIENT2='YOUR-ACCESS-TOKEN-FROM-RESPONSE'
```

## Configuration Details

### Kong Identity Setup

Terraform creates the following Kong Identity resources:

1. **Auth Server** (`konnect_auth_server.kafka_auth_server`)
   - Provides OAuth token issuance
   - Issuer URL is automatically generated
   - JWKS endpoint for token validation

2. **Kafka Scope** (`konnect_auth_server_scopes.kafka_scope`)
   - Scope name: `kafka`
   - Required for all OAuth tokens

3. **OAuth Clients**:
   - **Client1** (`kafka_client_1`): Full access to all topics
   - **Client2** (`kafka_client_2`): Limited access to specific topics

### Backend Cluster

The backend cluster connects to your Kafka cluster (e.g., Confluent Cloud) with:
- **Authentication**: SASL_PLAIN using environment variables (`KAFKA_USERNAME`, `KAFKA_PASSWORD`)
- **TLS**: Enabled for secure connections
- **Bootstrap Servers**: Configurable via `backend_cluster_bootstrap_servers` variable

### Virtual Cluster

The virtual cluster provides:
- **Namespace Prefix**: `my-` (hidden from clients)
- **ACL Mode**: `enforce_on_gateway` - policies enforced at the gateway level
- **DNS Label**: `vcluster`
- **Additional Topics**: Includes `extra_topic` in the namespace
- **Authentication**: OAuth Bearer only (SASL_PLAIN removed)

### Authentication

**OAuth Bearer**: Token-based authentication via Kong Identity
- Uses JWKS endpoint for token validation (auto-configured from auth server)
- Requires valid access token from Kong Identity
- Two clients with different permissions

### ACL Policies

**Client1 Policy** (`acl_topic_policy_u1`):
- **Condition**: `context.auth.principal.name == '<client1-id>'`
- **Permissions**: Allow describe, read, write on all topics (`*`)
- **Use Case**: Full administrative access

**Client2 Policy** (`acl_topic_policy_u2`):
- **Condition**: `context.auth.principal.name == '<client2-id>'`
- **Permissions**:
  - Describe: `topic`, `topic-encrypted`, `extra_topic`
  - Read: `topic` only
- **Use Case**: Limited read-only access for specific topics

### Record Filtering

**Skip Record Policy** (`skip_record`):
- **Condition**: `record.headers['internal'] == 'true' && context.auth.principal.name != '<client1-id>'`
- **Effect**: Records with header `internal=true` are only visible to Client1
- **Use Case**: Hide internal/sensitive records from limited-access clients

## Environment Variables Reference

### Required for Terraform Deployment

| Variable | Description | When to Set |
|----------|-------------|-------------|
| `KONNECT_TOKEN` | Your Konnect personal access token | Before `terraform apply` |
| `KAFKA_USERNAME` | Backend Kafka cluster username | Before `terraform apply` |
| `KAFKA_PASSWORD` | Backend Kafka cluster password | Before `terraform apply` |

### Generated by Terraform (Available via `terraform output`)

| Output | Description | Usage |
|--------|-------------|-------|
| `auth_server_id` | ID of the created auth server | Reference only |
| `auth_server_issuer_url` | Issuer URL from the auth server | Token generation |
| `scope_id` | ID of the created scope | Reference only |
| `client_id_1` | Client1 ID for authentication | Token generation |
| `client_secret_1` | Client1 secret for authentication | Token generation (sensitive) |
| `client_id_2` | Client2 ID for authentication | Token generation |
| `client_secret_2` | Client2 secret for authentication | Token generation (sensitive) |
| `token_endpoint` | OAuth token endpoint | Token generation |
| `jwks_endpoint` | JWKS endpoint for validation | Reference only |
| `event_gateway_id` | ID of the Event Gateway | Reference only |

### For Testing (After Token Generation)

| Variable | Description | When to Set |
|----------|-------------|-------------|
| `ACCESS_TOKEN_CLIENT1` | OAuth token for Client1 | After token generation |
| `ACCESS_TOKEN_CLIENT2` | OAuth token for Client2 | After token generation |

## Testing the Setup

### Connect with OAuth Bearer Token (Client1 - Full Access)

Produce messages to any topic:

```sh
kafka-console-producer --bootstrap-server localhost:19092 \
  --topic test-topic \
  --producer-property security.protocol=SASL_PLAINTEXT \
  --producer-property sasl.mechanism=OAUTHBEARER \
  --producer-property sasl.jaas.config='org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required oauth.access.token="'$ACCESS_TOKEN_CLIENT1'";' \
  --producer-property sasl.login.callback.handler.class=org.apache.kafka.common.security.oauthbearer.secured.OAuthBearerLoginCallbackHandler
```

Consume messages from any topic:

```sh
kafka-console-consumer --bootstrap-server localhost:19092 \
  --topic test-topic \
  --consumer-property security.protocol=SASL_PLAINTEXT \
  --consumer-property sasl.mechanism=OAUTHBEARER \
  --consumer-property sasl.jaas.config='org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required oauth.access.token="'$ACCESS_TOKEN_CLIENT1'";' \
  --consumer-property sasl.login.callback.handler.class=org.apache.kafka.common.security.oauthbearer.secured.OAuthBearerLoginCallbackHandler
```

### Connect with OAuth Bearer Token (Client2 - Limited Access)

Client2 can only read from the `topic` topic:

```sh
kafka-console-consumer --bootstrap-server localhost:19092 \
  --topic topic \
  --consumer-property security.protocol=SASL_PLAINTEXT \
  --consumer-property sasl.mechanism=OAUTHBEARER \
  --consumer-property sasl.jaas.config='org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required oauth.access.token="'$ACCESS_TOKEN_CLIENT2'";' \
  --consumer-property sasl.login.callback.handler.class=org.apache.kafka.common.security.oauthbearer.secured.OAuthBearerLoginCallbackHandler
```

**Note**: Client2 cannot produce messages or read from other topics due to ACL restrictions.

### Test Record Filtering

Client1 can see all records, including those with `internal=true` header:

```sh
# Produce a record with internal header (as Client1)
echo "internal-data" | kafka-console-producer --bootstrap-server localhost:19092 \
  --topic test-topic \
  --property "parse.key=false" \
  --property "key.separator=:" \
  --property "header.separator=|" \
  --property "headers=internal:true" \
  --producer-property security.protocol=SASL_PLAINTEXT \
  --producer-property sasl.mechanism=OAUTHBEARER \
  --producer-property sasl.jaas.config='org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required oauth.access.token="'$ACCESS_TOKEN_CLIENT1'";' \
  --producer-property sasl.login.callback.handler.class=org.apache.kafka.common.security.oauthbearer.secured.OAuthBearerLoginCallbackHandler
```

Client2 will NOT see records with `internal=true` header due to the skip record policy.

## Cleanup

To destroy all Terraform-managed resources (including Kong Identity resources):

```sh
cd event-gateway
terraform destroy
```

This will remove:
- Event Gateway and all its policies
- Virtual cluster and backend cluster
- Kong Identity auth server, scope, and clients

## Terraform Resources Created

The Terraform configuration creates the following resources:

### Kong Identity Resources

1. **Auth Server** (`konnect_auth_server.kafka_auth_server`)
   - OAuth token issuer
   - Auto-generated issuer URL and JWKS endpoint

2. **Scope** (`konnect_auth_server_scopes.kafka_scope`)
   - Kafka scope for authorization

3. **OAuth Clients**:
   - `konnect_auth_server_clients.kafka_client_1`: Full access client
   - `konnect_auth_server_clients.kafka_client_2`: Limited access client

### Event Gateway Resources

4. **Event Gateway** (`konnect_event_gateway.event_gateway_terraform`)
   - Main Event Gateway instance

5. **Backend Cluster** (`konnect_event_gateway_backend_cluster.backend_cluster`)
   - Connects to Confluent Cloud
   - SASL_PLAIN authentication with TLS

6. **Virtual Cluster** (`konnect_event_gateway_virtual_cluster.virtual_cluster`)
   - Namespace with `my-` prefix
   - OAuth Bearer authentication only
   - ACL enforcement mode
   - Auto-configured JWKS endpoint from auth server

7. **Listener** (`konnect_event_gateway_listener.listener`)
   - Listens on `0.0.0.0:19092-19192`

8. **Forwarding Policy** (`konnect_event_gateway_listener_policy_forward_to_virtual_cluster.forward_to_vcluster`)
   - Routes traffic to virtual cluster

9. **ACL Policies**:
   - `acl_topic_policy_u1`: Full access for Client1
   - `acl_topic_policy_u2`: Limited access for Client2

10. **Skip Record Policy** (`konnect_event_gateway_consume_policy_skip_record.skip_record`)
    - Filters records based on headers and principal

## Project Structure

```
.
├── .gitignore                          # Git ignore rules
├── README.md                           # This file
├── docker-compose.yml                  # Docker compose for local setup (if applicable)
├── konnect.env                         # Environment variables template
└── event-gateway/                      # Terraform configuration
    ├── main.tf                        # Main Terraform configuration
    │                                  # - Kong Identity resources (auth server, scope, clients)
    │                                  # - Event Gateway resource
    │                                  # - Backend cluster (Confluent Cloud)
    │                                  # - Virtual cluster with OAuth authentication
    │                                  # - ACL policies (Client1, Client2)
    │                                  # - Skip record policy
    │                                  # - Listener configuration
    │                                  # - Forwarding policy
    ├── providers.tf                   # Provider configuration
    ├── variables.tf                   # Variable definitions
    ├── outputs.tf                     # Output definitions
    ├── terraform.tfvars.example       # Example variable values
    └── terraform.tfvars               # Your actual values (gitignored)
```

## Quick Reference: Setup Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│ Step 1: Prepare Environment                                        │
├─────────────────────────────────────────────────────────────────────┤
│ export KONNECT_TOKEN='...'                                          │
│ export KAFKA_USERNAME='...'                                         │
│ export KAFKA_PASSWORD='...'                                         │
│ cd event-gateway                                                    │
│ cp terraform.tfvars.example terraform.tfvars                        │
│ # Edit terraform.tfvars                                             │
└─────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────┐
│ Step 2: Deploy with Terraform                                      │
├─────────────────────────────────────────────────────────────────────┤
│ terraform init                                                      │
│ terraform plan                                                      │
│ terraform apply                                                     │
│                                                                     │
│ Creates:                                                            │
│ ✓ Kong Identity (auth server, scope, 2 clients)                    │
│ ✓ Event Gateway with backend cluster                               │
│ ✓ Virtual cluster with OAuth authentication                        │
│ ✓ ACL policies for Client1 and Client2                             │
│ ✓ Listener on localhost:19092-19192                                │
└─────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────┐
│ Step 3: Generate OAuth Tokens                                      │
├─────────────────────────────────────────────────────────────────────┤
│ export TOKEN_ENDPOINT=$(terraform output -raw token_endpoint)      │
│ export CLIENT_ID_1=$(terraform output -raw client_id_1)            │
│ export CLIENT_SECRET_1=$(terraform output -raw client_secret_1)    │
│                                                                     │
│ curl -X POST "$TOKEN_ENDPOINT" \                                   │
│   -d "grant_type=client_credentials" \                             │
│   -d "client_id=$CLIENT_ID_1" \                                    │
│   -d "client_secret=$CLIENT_SECRET_1" \                            │
│   -d "scope=kafka"                                                 │
│                                                                     │
│ # Repeat for Client2                                               │
└─────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────┐
│ Step 4: Test Kafka Connections                                     │
├─────────────────────────────────────────────────────────────────────┤
│ # Use kafka-console-producer/consumer with OAUTHBEARER             │
│ # Client1: Full access (describe, read, write all topics)          │
│ # Client2: Limited access (describe specific, read 'topic' only)   │
└─────────────────────────────────────────────────────────────────────┘
```

## Key Features Demonstrated

### 1. Fully Automated Terraform Deployment
- **Kong Identity** and **Event Gateway** resources created in a single `terraform apply`
- No manual API calls required
- All resources managed as infrastructure-as-code

### 2. OAuth Bearer Authentication
- Modern token-based authentication via Kong Identity
- Auto-configured JWKS endpoint from auth server
- Two clients with different permission levels

### 3. Namespace Management
- Backend topics are prefixed with `my-`
- Virtual cluster hides the prefix from clients
- Clients interact with topics without the prefix

### 4. Fine-Grained Access Control
- **Client1**: Full access to all topics (describe, read, write)
- **Client2**: Restricted access (describe on specific topics, read on `topic` only)
- Policies enforced at the gateway level using client IDs

### 5. Record-Level Filtering
- Records with `internal=true` header are filtered for Client2
- Client1 can see all records
- Demonstrates content-based access control

### 6. Secure Backend Connection
- TLS-enabled connection to Confluent Cloud
- Credentials managed via environment variables
- SASL_PLAIN authentication to backend cluster

## Additional Resources

- [Kong Konnect Documentation](https://docs.konghq.com/konnect/)
- [Kong Identity Documentation](https://docs.konghq.com/konnect/identity/)
- [Kong Event Gateway Documentation](https://docs.konghq.com/konnect/event-gateway/)
- [Terraform Konnect Provider](https://registry.terraform.io/providers/Kong/konnect-beta/latest/docs)

## Troubleshooting

### Terraform Deployment Issues

- **Provider authentication fails**: Ensure `KONNECT_TOKEN` is set correctly in your `terraform.tfvars` file
- **Auth server name conflict**: Auth server names must be unique per organization and region. Change `auth_server_name` variable
- **Resource already exists**: Check if resources with the same name already exist. Use different names or import existing resources
- **Environment variables not set**: Ensure `KAFKA_USERNAME` and `KAFKA_PASSWORD` are exported before running `terraform apply`
- **Backend cluster connection fails**: Verify bootstrap servers and credentials are correct for your Kafka cluster

### Token Generation Issues

- **Token generation fails**:
  - Verify you're using the correct `client_id` and `client_secret` from `terraform output`
  - Ensure the token endpoint URL is correct
  - Check that the scope name is `kafka`
- **Invalid scope error**: The scope must be `kafka` as defined in the Terraform configuration
- **Token expired**: Tokens expire after 3600 seconds (1 hour). Generate a new token

### Connection Issues

- **Cannot connect to localhost:19092**:
  - Ensure the Event Gateway is running (check Konnect UI)
  - Verify the listener is properly configured
  - Check that ports 19092-19192 are not blocked by firewall
- **Authentication fails**:
  - Verify you're using a valid, non-expired OAuth token
  - Ensure the token was generated with the correct client credentials
  - Check that the SASL mechanism is set to `OAUTHBEARER`
- **ACL denied**:
  - Check that the client has the necessary permissions in the ACL policies
  - Client1 has full access to all topics
  - Client2 can only describe specific topics and read from `topic`
  - Verify the operation (describe/read/write) is allowed for the client
- **Topic not found**:
  - Remember that topics are prefixed with `my-` in the backend
  - The virtual cluster hides this prefix from clients
  - When connecting, use topic names WITHOUT the `my-` prefix
  - Example: Backend topic `my-test-topic` is accessed as `test-topic`

### Record Filtering Issues

- **Records not being filtered**:
  - Verify the record has the header `internal=true`
  - Check that you're using Client2 (Client1 can see all records)
  - Ensure the skip record policy is properly deployed
