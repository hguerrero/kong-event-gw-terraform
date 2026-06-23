#!/bin/bash
# Fetches an OAuth token from Kong Identity and outputs it in the format
# expected by kafkactl's generic token provider.
# Values are read from Terraform outputs (event-gateway/); set CLIENT_ID,
# CLIENT_SECRET, or TOKEN_ENDPOINT env vars to override.
# Usage: ./get-token.sh [scope]

SCOPE=${1:-kafka}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/event-gateway"

if [[ -z "${CLIENT_ID}" ]]; then
  CLIENT_ID="$(terraform -chdir="${TF_DIR}" output -raw client_id_1 2>/dev/null)"
fi

if [[ -z "${CLIENT_SECRET}" ]]; then
  CLIENT_SECRET="$(terraform -chdir="${TF_DIR}" output -raw client_secret_1 2>/dev/null)"
fi

if [[ -z "${TOKEN_ENDPOINT}" ]]; then
  TOKEN_ENDPOINT="$(terraform -chdir="${TF_DIR}" output -raw token_endpoint 2>/dev/null)"
fi

if [[ -z "${CLIENT_ID}" || -z "${CLIENT_SECRET}" || -z "${TOKEN_ENDPOINT}" ]]; then
  echo "Error: could not resolve CLIENT_ID, CLIENT_SECRET, or TOKEN_ENDPOINT from Terraform outputs." >&2
  exit 1
fi

curl -s --fail -X POST "${TOKEN_ENDPOINT}" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=${CLIENT_ID}" \
  -d "client_secret=${CLIENT_SECRET}" \
  -d "scope=${SCOPE}" | jq '{"token": .access_token}'
