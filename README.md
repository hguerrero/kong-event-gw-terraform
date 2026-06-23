# Kong Event Gateway with Kong Identity

This project demonstrates how to set up Kong Event Gateway with Kong Identity authentication using Terraform, including virtual clusters, ACL policies, and OAuth Bearer authentication.

## Architecture Overview

This setup creates a complete Kafka proxy solution with:

- **Kong Identity (Terraform-managed)**:
  - Auth server for OAuth token issuance
  - Kafka scope for authorization
  - Two OAuth clients (Client1 and Client2) with different permissions
- **Backend Cluster**: Connects to a Kafka cluster with anonymous authentication (for demo purposes)
- **Virtual Cluster**: Provides namespace isolation with prefix management (`internal-` prefix)
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
- **Kafka Cluster**: Access to a Kafka cluster with bootstrap servers
- **Docker**: For running Kafka client tests

### Getting Your Konnect Token

1. Create a new personal access token by opening the Konnect PAT page and selecting Generate Token
2. Export your token to environment variables used by this Terraform project:
   ```sh
   export KONNECT_TOKEN='YOUR_KONNECT_PAT'
   export TF_VAR_konnect_token="$KONNECT_TOKEN"
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

Set your Konnect token as environment variables:

```sh
export KONNECT_TOKEN='YOUR_KONNECT_PAT'
export TF_VAR_konnect_token="$KONNECT_TOKEN"
```

**Note**: The current configuration uses anonymous authentication for the backend cluster (for demo purposes). For production use, you should configure proper authentication in the Terraform configuration.

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
   - Backend cluster connection to your configured Kafka bootstrap servers
  - Virtual cluster with namespace configuration and OAuth authentication
  - ACL policies for Client1 (full access) and Client2 (limited access)
  - Skip record policy for filtering
  - Listener on localhost:19092-19192
  - Forwarding policy to virtual cluster
   - Data plane certificate resources (generated, registered, and written to `config/certs`)

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

## Configuration Details

### Kong Identity Setup

Terraform creates the following Kong Identity resources:

1. **Auth Server** (`konnect_identity_auth_server.kafka_auth_server`)
   - Provides OAuth token issuance
   - Issuer URL is automatically generated
   - JWKS endpoint for token validation

2. **Kafka Scope** (`konnect_identity_auth_server_scope.kafka_scope`)
   - Scope name: `kafka`
   - Required for all OAuth tokens

3. **OAuth Clients**:
   - **Client1** (`kafka_client_1`): Full access to all topics
   - **Client2** (`kafka_client_2`): Limited access to specific topics

### Backend Cluster

The backend cluster connects to your Kafka cluster with:
- **Authentication**: Anonymous (for demo purposes - configure proper authentication for production)
- **TLS**: Disabled (for demo purposes - enable for production)
- **Bootstrap Servers**: Configurable via `backend_cluster_bootstrap_servers` variable

### Virtual Cluster

The virtual cluster provides:
- **Namespace Prefix**: `internal-` (hidden from clients)
- **ACL Mode**: `enforce_on_gateway` - policies enforced at the gateway level
- **DNS Label**: `vcluster`
- **Additional Topics**: Exposes selected pre-created backend topics from `kafka/config/topics.txt`
- **Authentication**: OAuth Bearer only

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
   - Describe: `nw.ops.test.hello-world.v1`, `infosec.security.fraud.risk-scores.v3`, `nw.ledger.transactions.high-value-wire-transfers.v1`
   - Read: `nw.ops.test.hello-world.v1` only
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
| `TF_VAR_konnect_token` | Terraform input variable for Konnect PAT | Before `terraform apply` |

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

## Testing the Setup

### Prepare Client Configuration

Before testing, you need to create a client configuration file with your OAuth credentials:

1. Copy the example configuration file:
   ```sh
   cp client-config.properties.example client1-config.properties
   ```

2. Edit `client1-config.properties` and replace the placeholder values with the ones produced by Terraform:
   - Replace `<YOUR_AUTH_SERVER_TOKEN_ENDPOINT>` with the value from `terraform output -raw token_endpoint`
   - Replace `<YOUR_CLIENT_ID>` with the value from `terraform output -raw client_id_1`
   - Replace `<YOUR_CLIENT_SECRET>` with the value from `terraform output -raw client_secret_1`

   Your file should look like this:
   ```properties
   security.protocol=SASL_PLAINTEXT
   sasl.mechanism=OAUTHBEARER
   sasl.login.callback.handler.class=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginCallbackHandler
      sasl.oauthbearer.token.endpoint.url=https://your-auth-server.konghq.com/oauth/token
   sasl.jaas.config=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required \
       clientId="your-actual-client-id" \
       clientSecret="your-actual-client-secret" \
       scope="kafka";
   ```

3. (Optional) For Client2, create a separate configuration file:
   ```sh
   cp client-config.properties.example client2-config.properties
   ```

   Then replace the values with Client2 credentials:
   - Use `terraform output -raw client_id_2` for the client ID
   - Use `terraform output -raw client_secret_2` for the client secret

### Test with Docker (Client1 - Full Access)

#### Produce Messages

```sh
docker run -it --rm --name kafka-client \
  -v ./client1-config.properties:/opt/etc/client-config.properties \
  apache/kafka \
  /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server host.docker.internal:19092 \
   --topic nw.ops.test.hello-world.v1 \
  --producer.config /opt/etc/client-config.properties
```

Type your messages and press Enter after each one. Press Ctrl+C to exit.

#### Consume Messages

```sh
docker run -it --rm --name kafka-client \
  -v ./client1-config.properties:/opt/etc/client-config.properties \
  apache/kafka \
  /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server host.docker.internal:19092 \
   --topic nw.ops.test.hello-world.v1 \
  --from-beginning \
  --consumer.config /opt/etc/client-config.properties
```

### Test with Docker (Client2 - Limited Access)

Client2 can only read from the `nw.ops.test.hello-world.v1` topic:

```sh
docker run -it --rm --name kafka-client \
  -v ./client2-config.properties:/opt/etc/client-config.properties \
  apache/kafka \
  /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server host.docker.internal:19092 \
   --topic nw.ops.test.hello-world.v1 \
  --from-beginning \
  --consumer.config /opt/etc/client-config.properties
```

**Note**: Client2 cannot produce messages or read from other topics due to ACL restrictions.

### Test Record Filtering

Client1 can see all records, including those with `internal=true` header:

```sh
# Produce a record with internal header (as Client1)
echo "internal-data" | docker run -i --rm --name kafka-client \
  -v ./client1-config.properties:/opt/etc/client-config.properties \
  apache/kafka \
  /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server host.docker.internal:19092 \
   --topic nw.ops.test.hello-world.v1 \
  --property "parse.key=false" \
  --property "key.separator=:" \
  --property "header.separator=|" \
  --property "headers=internal:true" \
  --producer.config /opt/etc/client-config.properties
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

1. **Auth Server** (`konnect_identity_auth_server.kafka_auth_server`)
   - OAuth token issuer
   - Auto-generated issuer URL and JWKS endpoint

2. **Scope** (`konnect_identity_auth_server_scope.kafka_scope`)
   - Kafka scope for authorization

3. **OAuth Clients**:
   - `konnect_identity_auth_server_client.kafka_client_1`: Full access client
   - `konnect_identity_auth_server_client.kafka_client_2`: Limited access client

### Event Gateway Resources

4. **Event Gateway** (`konnect_event_gateway.event_gateway_terraform`)
   - Main Event Gateway instance

5. **Backend Cluster** (`konnect_event_gateway_backend_cluster.backend_cluster`)
   - Connects to your Kafka cluster
   - Anonymous authentication (demo configuration)

6. **Virtual Cluster** (`konnect_event_gateway_virtual_cluster.virtual_cluster`)
   - Namespace with `internal-` prefix
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

11. **Data Plane Certificate Resources**:
   - `tls_private_key.data_plane`: Private key generation
   - `tls_self_signed_cert.data_plane`: Self-signed certificate generation
   - `local_file.data_plane_cert` / `local_file.data_plane_key`: Writes PEM files to `config/certs`
   - `konnect_event_gateway_data_plane_certificate.data_plane_cert`: Registers certificate in Konnect

## Project Structure

```
.
├── .gitignore                          # Git ignore rules
├── README.md                           # This file
├── client-config.properties.example    # Example Kafka client configuration
├── docker-compose.yml                  # Docker compose for local Event Gateway setup
├── get-token.sh                        # Helper script to fetch OAuth tokens from Terraform outputs
├── kafka/                              # Local Kafka + schema registry stack
├── konnect.env                         # Environment variables for docker-compose
├── konnect.env.example                 # Template for konnect.env
└── event-gateway/                      # Terraform configuration
    ├── main.tf                        # Main Terraform configuration
    │                                  # - Kong Identity resources (auth server, scope, clients)
    │                                  # - Event Gateway resource
    │                                  # - Backend cluster
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
│ Step 3: Prepare Client Configuration                              │
├─────────────────────────────────────────────────────────────────────┤
│ cp client-config.properties.example client1-config.properties     │
│ # Edit client1-config.properties with values from terraform output │
│ # - token_endpoint, client_id_1, client_secret_1                  │
└─────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────┐
│ Step 4: Test Kafka Connections with Docker                        │
├─────────────────────────────────────────────────────────────────────┤
│ # Producer:                                                         │
│ docker run -it --rm -v ./client1-config.properties:/opt/etc/...   │
│   apache/kafka /opt/kafka/bin/kafka-console-producer.sh ...       │
│                                                                     │
│ # Consumer:                                                         │
│ docker run -it --rm -v ./client1-config.properties:/opt/etc/...   │
│   apache/kafka /opt/kafka/bin/kafka-console-consumer.sh ...       │
│                                                                     │
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
- Backend topics are prefixed with `internal-`
- Virtual cluster hides the prefix from clients
- Clients interact with topics without the prefix

### 4. Fine-Grained Access Control
- **Client1**: Full access to all topics (describe, read, write)
- **Client2**: Restricted access (describe specific Kafka bootstrap topics, read only on `nw.ops.test.hello-world.v1`)
- Policies enforced at the gateway level using client IDs

### 5. Record-Level Filtering
- Records with `internal=true` header are filtered for Client2
- Client1 can see all records
- Demonstrates content-based access control

### 6. Docker-Based Testing
- Easy testing with Docker containers
- Configuration file-based authentication
- No need to manually construct JAAS configurations

## Additional Resources

- [Kong Konnect Documentation](https://docs.konghq.com/konnect/)
- [Kong Identity Documentation](https://docs.konghq.com/konnect/identity/)
- [Kong Event Gateway Documentation](https://docs.konghq.com/konnect/event-gateway/)
- [Terraform Konnect Provider](https://registry.terraform.io/providers/Kong/konnect/latest/docs)

## Troubleshooting

### Terraform Deployment Issues

- **Provider authentication fails**: Ensure `TF_VAR_konnect_token` is exported or `konnect_token` is set in `terraform.tfvars`
- **Auth server name conflict**: Auth server names must be unique per organization and region. Change `auth_server_name` variable
- **Resource already exists**: Check if resources with the same name already exist. Use different names or import existing resources
- **Backend cluster connection fails**: Verify bootstrap servers are correct for your Kafka cluster

### Client Configuration Issues

- **Client configuration fails**:
  - Verify you've copied `client-config.properties.example` to `client1-config.properties`
  - Ensure you've replaced all placeholder values (`<YOUR_...>`) with actual values from `terraform output`
  - Check that the token endpoint URL is correct (from `terraform output -raw token_endpoint`)
  - Verify client_id and client_secret are correct (from `terraform output -raw client_id_1` and `client_secret_1`)
- **Invalid scope error**: The scope must be `kafka` as defined in the Terraform configuration

### Connection Issues

- **Cannot connect to localhost:19092**:
  - Ensure the Event Gateway is running (check Konnect UI)
  - Verify the listener is properly configured
  - Check that ports 19092-19192 are not blocked by firewall
- **Authentication fails**:
  - Verify your client configuration file has the correct values
  - Check that the SASL mechanism is set to `OAUTHBEARER` in the config file
  - Ensure the token endpoint URL is accessible
  - OAuth tokens are automatically refreshed by the Kafka client using the configuration
- **ACL denied**:
  - Check that the client has the necessary permissions in the ACL policies
  - Client1 has full access to all topics
   - Client2 can only describe specific topics and read from `nw.ops.test.hello-world.v1`
  - Verify the operation (describe/read/write) is allowed for the client
- **Topic not found**:
  - Remember that topics are prefixed with `internal-` in the backend
  - The virtual cluster hides this prefix from clients
   - Pre-created Kafka topics can be exposed via virtual-cluster additional topic mappings
   - This setup exposes topics such as `nw.ops.test.hello-world.v1` for ACL testing
- **Docker connection issues**:
  - Ensure you're using `host.docker.internal:19092` as the bootstrap server in Docker commands
  - On Linux, you may need to use `--network host` or the host's IP address instead of `host.docker.internal`
  - Verify the volume mount path is correct: `-v ./client1-config.properties:/opt/etc/client-config.properties`

### Record Filtering Issues

- **Records not being filtered**:
  - Verify the record has the header `internal=true`
  - Check that you're using Client2 (Client1 can see all records)
  - Ensure the skip record policy is properly deployed
