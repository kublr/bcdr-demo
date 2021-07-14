#!/bin/bash

# Authenticate with Kublr Control Plane

eval "$(curl -s \
  -d "grant_type=password" \
  -d "scope=openid" \
  -d "client_id=kublr-ui" \
  -d "username=${KCP_USERNAME}" \
  -d "password=${KCP_PASSWORD}" \
  "${KCP_URL}/auth/realms/kublr-ui/protocol/openid-connect/token" | \
  jq -r '"REFRESH_TOKEN="+.refresh_token,"TOKEN="+.access_token,"ID_TOKEN="+.id_token')"

function downloadConfig() {
  space="${1}"
  cluster="${2}"

  if ! curl -ksSf -XGET -H "Authorization: Bearer ${TOKEN}" \
    "${KCP_URL}/api/spaces/${space}/cluster/${cluster}/admin-config" > \
    "tmp-config-${cluster}.yaml" ; then
    return 1
  fi

  mv -f "tmp-config-${cluster}.yaml" "config-${cluster}.yaml"

  chmod 600 "config-${cluster}.yaml"
}

# Download Kubernetes kubeconfig file for the managed cluster
downloadConfig "${SPACE_AZR}" "${CLUSTER_AZR}"

# Download Kubernetes kubeconfig file for the managed cluster
downloadConfig "${SPACE_AWS}" "${CLUSTER_AWS}"
