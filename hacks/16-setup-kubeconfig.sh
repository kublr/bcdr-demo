#!/bin/bash

cat > config.yaml <<EOF
current-context: w
contexts:
- name: z
  context:
    cluster: ${CLUSTER_AZR}
    user: ${CLUSTER_AZR}-admin-token
- name: w
  context:
    cluster: ${CLUSTER_AWS}
    user: ${CLUSTER_AWS}-admin-token
    namespace: echoserver
EOF

export KUBECONFIG="$(pwd)/config.yaml:$(pwd)/config-${CLUSTER_AZR}.yaml:$(pwd)/config-${CLUSTER_AWS}.yaml"

echo "KUBECONFIG=${KUBECONFIG}"
