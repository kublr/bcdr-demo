#!/bin/sh

# Authenticate with Kublr Control Plane

eval "$(curl -s \
  -d "grant_type=password" \
  -d "scope=openid" \
  -d "client_id=kublr-ui" \
  -d "username=${KCP_USERNAME}" \
  -d "password=${KCP_PASSWORD}" \
  "${KCP_URL}/auth/realms/kublr-ui/protocol/openid-connect/token" | \
  jq -r '"REFRESH_TOKEN="+.refresh_token,"TOKEN="+.access_token,"ID_TOKEN="+.id_token')"

# Download Kubernetes kubeconfig file

curl -k -s -XPOST -H 'content-type: application/x-yaml' -H "Authorization: Bearer ${TOKEN}" --data-binary '@-' \
  "${KCP_URL}/api/spaces/${SPACE_AZR}/cluster" < "bcdr-demo/clusters/${CLUSTER_AZR}.yaml"
