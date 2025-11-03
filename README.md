# Kong Event Gateway with Kong Identity

This project demonstrates how to set up Kong Event Gateway with Kong Identity authentication, including virtual clusters, ACL policies, and multiple authentication methods.

## Architecture Overview

This setup creates a complete Kafka proxy solution with:

- **Backend Cluster**: Connects to Confluent Cloud (or any Kafka cluster) using SASL_PLAIN authentication
- **Virtual Cluster**: Provides namespace isolation with prefix management (`my-` prefix)
- **Multiple Authentication Methods**:
  - SASL_PLAIN for username/password authentication (user1, user2)
  - OAuth Bearer tokens via Kong Identity
- **ACL Policies**: Fine-grained access control per user
- **Record Filtering**: Skip records based on headers and principals
- **Listener Configuration**: Local listener on ports 19092-19192

## Workflow Overview

The setup follows this order:

1. **First: Kong Identity Setup** (Manual via Konnect API)
   - Create auth server
   - Configure scopes
   - Create client credentials

2. **Second: Event Gateway Deployment** (Terraform)
   - Deploy Event Gateway with backend cluster
   - Configure virtual cluster with authentication
   - Set up ACL policies
   - Configure listeners and forwarding policies

## Prerequisites

- **Konnect Account**: This project requires a Konnect personal access token
- **Terraform**: Version 1.0 or higher

### Getting Your Konnect Token

1. Create a new personal access token by opening the Konnect PAT page and selecting Generate Token
2. Export your token to an environment variable:
   ```sh
   export KONNECT_TOKEN='YOUR_KONNECT_PAT'
   ```

## Setup Instructions

### Step 1: Create Kong Identity Resources

Before deploying the Event Gateway with Terraform, you need to set up Kong Identity authentication.

#### 1.1. Create an auth server in Kong Identity

Before you can configure the SASL_OAUTHBEARER authentication, you must first create an auth server in Kong Identity. We recommend creating different auth servers for different environments or subsidiaries. The auth server name is unique per each organization and each Konnect region.

Create an auth server using the `/v1/auth-servers` endpoint:

```sh
 curl -X POST "https://us.api.konghq.com/v1/auth-servers" \
     -H "Authorization: Bearer $KONNECT_TOKEN"\
     -H "Content-Type: application/json" \
     --json '{
       "name": "Kafka Dev",
       "audience": "http://kafka.dev",
       "description": "Auth server for the Kafka dev environment"
     }'
```

Export the auth server ID and issuer URL:

```sh
export AUTH_SERVER_ID='YOUR-AUTH-SERVER-ID'
export ISSUER_URL='YOUR-ISSUER-URL'
```

#### 1.2. Configure the auth server with scopes

Configure a scope in your auth server using the `/v1/auth-servers/$AUTH_SERVER_ID/scopes` endpoint

```sh
 curl -X POST "https://us.api.konghq.com/v1/auth-servers/$AUTH_SERVER_ID/scopes" \
     -H "Authorization: Bearer $KONNECT_TOKEN"\
     -H "Content-Type: application/json" \
     --json '{
       "name": "kafka",
       "description": "Scope to test Kong Identity",
       "default": false,
       "include_in_metadata": false,
       "enabled": true
     }'
```

Export your scope ID:

```sh
export SCOPE_ID='YOUR-SCOPE-ID'
```

#### 1.3. Create a client in the auth server

The client is the machine-to-machine credential. In this tutorial, Konnect will autogenerate the client ID and secret, but you can alternatively specify one yourself.

Configure the client using the `/v1/auth-servers/$AUTH_SERVER_ID/clients` endpoint:

```sh
 curl -X POST "https://us.api.konghq.com/v1/auth-servers/$AUTH_SERVER_ID/clients" \
     -H "Authorization: Bearer $KONNECT_TOKEN"\
     -H "Content-Type: application/json" \
     --json '{
       "name": "Client",
       "grant_types": [
         "client_credentials"
       ],
       "allow_all_scopes": false,
       "allow_scopes": [
         "'$SCOPE_ID'"
       ],
       "access_token_duration": 3600,
       "id_token_duration": 3600,
       "response_types": [
         "id_token",
         "token"
       ]
     }'
```

Export your client secret and client ID:

```sh
export CLIENT_SECRET='YOUR-CLIENT-SECRET'
export CLIENT_ID='YOUR-CLIENT-ID'
```

#### 1.4. Verify your Kong Identity setup

At this point, you should have the following information from the Kong Identity setup:

- `AUTH_SERVER_ID` - The ID of your auth server
- `ISSUER_URL` - The issuer URL from the auth server
- `SCOPE_ID` - The ID of the Kafka scope
- `CLIENT_ID` - The client ID for authentication
- `CLIENT_SECRET` - The client secret for authentication

### Step 2: Deploy Event Gateway with Terraform

Now that Kong Identity is set up, you can deploy the Event Gateway using Terraform.

#### 2.1. Configure Terraform Variables

```sh
cd event-gateway
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your Konnect token and backend cluster details
```

Required variables in `terraform.tfvars`:
- `konnect_token`: Your Konnect personal access token
- `backend_cluster_bootstrap_servers`: List of Kafka bootstrap servers (e.g., Confluent Cloud endpoints)

#### 2.2. Set Environment Variables

The configuration uses environment variables for sensitive credentials:

```sh
# Backend cluster credentials (Confluent Cloud or your Kafka cluster)
export KAFKA_USERNAME='your-kafka-username'
export KAFKA_PASSWORD='your-kafka-password'

# Virtual cluster user credentials
export USER1_PASSWORD='password-for-user1'
export USER2_PASSWORD='password-for-user2'
```

#### 2.3. Update OAuth JWKS Endpoint

In `event-gateway/main.tf`, update the JWKS endpoint (line 132) with your Kong Identity auth server's JWKS URL:

```hcl
jwks = {
    endpoint = "https://YOUR-AUTH-SERVER.us.identity.konghq.com/auth/.well-known/jwks"
    timeout = "1s"
}
```

You can find this URL from your auth server's issuer URL.

#### 2.4. Initialize and Apply Terraform

```sh
terraform init
terraform plan
terraform apply
```

This will create:
- Event Gateway instance
- Backend cluster connection to Confluent Cloud
- Virtual cluster with namespace configuration
- ACL policies for user1 and user2
- Skip record policy for filtering
- Listener on localhost:19092-19192
- Forwarding policy to virtual cluster

#### 2.5. View Outputs

```sh
terraform output
```

### Step 3: Generate an Access Token

The Gateway Service requires an access token from the client to access the Service. Generate a token for the client by making a call to the issuer URL:

```sh
curl -X POST "$ISSUER_URL/oauth/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=$CLIENT_ID" \
  -d "client_secret=$CLIENT_SECRET" \
  -d "scope=kafka"
```

Export your access token:

```sh
export ACCESS_TOKEN='YOUR-ACCESS-TOKEN'
```

## Configuration Details

### Backend Cluster

The backend cluster connects to your Kafka cluster (e.g., Confluent Cloud) with:
- **Authentication**: SASL_PLAIN using environment variables
- **TLS**: Enabled for secure connections
- **Bootstrap Servers**: Configurable via `backend_cluster_bootstrap_servers` variable

### Virtual Cluster

The virtual cluster provides:
- **Namespace Prefix**: `my-` (hidden from clients)
- **ACL Mode**: `enforce_on_gateway` - policies enforced at the gateway level
- **DNS Label**: `vcluster`
- **Additional Topics**: Includes `extra_topic` in the namespace

### Authentication Methods

1. **SASL_PLAIN**: Username/password authentication
   - `user1`: Full access (describe, read, write) to all topics
   - `user2`: Limited access (describe on specific topics, read on `topic`)

2. **OAuth Bearer**: Token-based authentication via Kong Identity
   - Uses JWKS endpoint for token validation
   - Requires valid access token from Kong Identity

### ACL Policies

**User1 Policy** (`acl_topic_policy1`):
- **Condition**: `context.auth.principal.name == 'user1'`
- **Permissions**: Allow describe, read, write on all topics (`*`)

**User2 Policy** (`acl_topic_policy2`):
- **Condition**: `context.auth.principal.name == 'user2'`
- **Permissions**:
  - Describe: `topic`, `topic-encrypted`, `extra_topic`
  - Read: `topic` only

### Record Filtering

**Skip Record Policy**:
- **Condition**: `record.headers['internal'] == 'true' && context.auth.principal.name != 'user1'`
- **Effect**: Records with header `internal=true` are only visible to `user1`

## Environment Variables Reference

| Variable | Description | Required |
|----------|-------------|----------|
| `KONNECT_TOKEN` | Your Konnect personal access token | Yes |
| `KAFKA_USERNAME` | Backend Kafka cluster username | Yes |
| `KAFKA_PASSWORD` | Backend Kafka cluster password | Yes |
| `USER1_PASSWORD` | Password for virtual cluster user1 | Yes |
| `USER2_PASSWORD` | Password for virtual cluster user2 | Yes |
| `AUTH_SERVER_ID` | ID of the created auth server | Yes (after creation) |
| `ISSUER_URL` | Issuer URL from the auth server | Yes (after creation) |
| `SCOPE_ID` | ID of the created scope | Yes (after creation) |
| `CLIENT_ID` | Client ID for authentication | Yes (after creation) |
| `CLIENT_SECRET` | Client secret for authentication | Yes (after creation) |
| `ACCESS_TOKEN` | Generated OAuth access token | Yes (for API calls) |

## Cleanup

### Destroy Event Gateway

To destroy the Terraform-managed Event Gateway:

```sh
cd event-gateway
terraform destroy
```

### Clean up Kong Identity Resources

Kong Identity resources were created manually via the API. To clean them up, you'll need to delete them via the Konnect API or UI:

1. Delete the client
2. Delete the scope
3. Delete the auth server

Or use the Konnect UI to manage these resources.

## Testing the Setup

### Connect with SASL_PLAIN (user1)

```sh
kafka-console-producer --bootstrap-server localhost:19092 \
  --topic my-test-topic \
  --producer-property security.protocol=SASL_PLAINTEXT \
  --producer-property sasl.mechanism=PLAIN \
  --producer-property sasl.jaas.config='org.apache.kafka.common.security.plain.PlainLoginModule required username="user1" password="'$USER1_PASSWORD'";'
```

### Connect with SASL_PLAIN (user2)

```sh
kafka-console-consumer --bootstrap-server localhost:19092 \
  --topic my-topic \
  --consumer-property security.protocol=SASL_PLAINTEXT \
  --consumer-property sasl.mechanism=PLAIN \
  --consumer-property sasl.jaas.config='org.apache.kafka.common.security.plain.PlainLoginModule required username="user2" password="'$USER2_PASSWORD'";'
```

### Connect with OAuth Bearer Token

```sh
kafka-console-consumer --bootstrap-server localhost:19092 \
  --topic my-test-topic \
  --consumer-property security.protocol=SASL_PLAINTEXT \
  --consumer-property sasl.mechanism=OAUTHBEARER \
  --consumer-property sasl.jaas.config='org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required oauth.access.token="'$ACCESS_TOKEN'";' \
  --consumer-property sasl.login.callback.handler.class=org.apache.kafka.common.security.oauthbearer.secured.OAuthBearerLoginCallbackHandler
```

## Terraform Resources Created

The Terraform configuration creates the following resources:

1. **Event Gateway** (`konnect_event_gateway.event_gateway_terraform`)
   - Main Event Gateway instance

2. **Backend Cluster** (`konnect_event_gateway_backend_cluster.backend_cluster`)
   - Connects to Confluent Cloud
   - SASL_PLAIN authentication with TLS

3. **Virtual Cluster** (`konnect_event_gateway_virtual_cluster.virtual_cluster`)
   - Namespace with `my-` prefix
   - SASL_PLAIN and OAuth Bearer authentication
   - ACL enforcement mode

4. **Listener** (`konnect_event_gateway_listener.listener`)
   - Listens on `0.0.0.0:19092-19192`

5. **Forwarding Policy** (`konnect_event_gateway_listener_policy_forward_to_virtual_cluster.forward_to_vcluster`)
   - Routes traffic to virtual cluster

6. **ACL Policies**:
   - `acl_topic_policy_u1`: Full access for user1
   - `acl_topic_policy_u2`: Limited access for user2

7. **Skip Record Policy** (`konnect_event_gateway_consume_policy_skip_record.skip_record`)
   - Filters records based on headers and principal

## Additional Resources

- [Kong Konnect Documentation](https://docs.konghq.com/konnect/)
- [Kong Identity Documentation](https://docs.konghq.com/konnect/identity/)
- [Terraform Konnect Provider](https://registry.terraform.io/providers/Kong/konnect-beta/latest/docs)

## Project Structure

```
.
├── .gitignore                          # Git ignore rules
├── README.md                           # This file
├── docker-compose.yml                  # Docker compose for local setup (if applicable)
├── konnect.env                         # Environment variables template
└── event-gateway/                      # Terraform configuration
    ├── main.tf                        # Main Terraform configuration
    │                                  # - Event Gateway resource
    │                                  # - Backend cluster (Confluent Cloud)
    │                                  # - Virtual cluster with namespace
    │                                  # - ACL policies (user1, user2)
    │                                  # - Skip record policy
    │                                  # - Listener configuration
    │                                  # - Forwarding policy
    ├── providers.tf                   # Provider configuration
    ├── variables.tf                   # Variable definitions
    ├── outputs.tf                     # Output definitions
    ├── terraform.tfvars.example       # Example variable values
    └── terraform.tfvars               # Your actual values (gitignored)
```

## Troubleshooting

### Kong Identity Setup Issues

- **Auth server creation fails**: Ensure `KONNECT_TOKEN` is valid and has the necessary permissions
- **Auth server name conflict**: Auth server names must be unique per organization and region. Use a different name
- **Scope creation fails**: Verify the `AUTH_SERVER_ID` is correct
- **Client creation fails**: Ensure the `SCOPE_ID` is valid and the scope is enabled

### Terraform Issues

- **Provider authentication fails**: Ensure `KONNECT_TOKEN` is set correctly in your `terraform.tfvars` file
- **Resource already exists**: Check if an Event Gateway with the same name already exists. Use a different name or import the existing resource
- **Environment variables not set**: Ensure all required environment variables (`KAFKA_USERNAME`, `KAFKA_PASSWORD`, `USER1_PASSWORD`, `USER2_PASSWORD`) are exported before running `terraform apply`
- **JWKS endpoint error**: Verify the JWKS endpoint URL in `main.tf` matches your Kong Identity auth server

### Token Generation Issues

- **Token generation fails**: Verify client credentials (`CLIENT_ID` and `CLIENT_SECRET`) are correct
- **Invalid scope error**: Ensure the scope name in the token request matches the scope created in Kong Identity

### Connection Issues

- **Cannot connect to localhost:19092**: Ensure the Event Gateway is running and the listener is properly configured
- **Authentication fails**: Verify user credentials are correct and match the environment variables
- **ACL denied**: Check that the user has the necessary permissions in the ACL policies for the requested operation and topic
- **Topic not found**: Remember that topics are prefixed with `my-` in the backend. The virtual cluster hides this prefix from clients
