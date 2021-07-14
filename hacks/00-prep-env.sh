# Prepare common env vars to use

echo "The script will set all required environment variables for the follow-up scripts."
echo "By default it will set everything up for a cluster name 'devops-demo-us-east-1' and"
echo "domain name 'devops-demo-us-east-1.workshop.kublr.com'."
echo
echo "You can run it as '. devops-demo/hacks/00-prep-env.sh my-cluster my-domain.com' to"
echo "configure scripts for other domains."
echo
echo "The scrips also require KCP_USERNAME, KCP_PASSWORD, and KCP_URL environment variables"
echo "configured correctly to work."
echo

export KCP_USERNAME="${KCP_USERNAME:-"admin"}"
# export KCP_PASSWORD=
# export KCP_URL="${KCP_URL-"https://kcp.example.com"}"

export SPACE_AZR="${SPACE_AZR:-"default"}"
export CLUSTER_AZR="${CLUSTER_AZR:-"demo-bcdr-azr"}"

export SPACE_AWS="${SPACE_AWS:-"default"}"
export CLUSTER_AWS="${CLUSTER_AWS:-"demo-bcdr-aws"}"

# The resource group may be per cluster, or the same for multiple clusters
export AZURE_BACKUP_RESOURCE_GROUP="${AZURE_BACKUP_RESOURCE_GROUP:-velero_backups_test}"
# The storage account may be per cluster, or the same for multiple clusters
export AZURE_STORAGE_ACCOUNT_ID="${AZURE_STORAGE_ACCOUNT_ID:-velero25e5797367db}"
# Containers should be different for different backup locations
export BLOB_CONTAINER="velero-${CLUSTER_AZR}"
# Azure API Connection Credentials
export AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-...}"
export AZURE_TENANT_ID="${AZURE_TENANT_ID:-...}"
export AZURE_CLIENT_ID="${AZURE_CLIENT_ID:-...}"
export AZURE_CLIENT_SECRET="${AZURE_CLIENT_SECRET:-...}"

# AWS

export AWS_BUCKET="${AWS_BUCKET:-"velero-backups-test"}"
export AWS_REGION="${AWS_REGION:-"us-east-1"}"

export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-...}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-...}"

if [ -z "${KCP_URL}" ] ; then
    echo "ERROR: KCP_URL environment variable is not defined"
    return 1
fi

if [ -z "${KCP_PASSWORD}" ] ; then
    echo "ERROR: KCP_PASSWORD environment variable is not defined"
    return 1
fi

export KUBECONFIG="$(pwd)/config.yaml:$(pwd)/config-${CLUSTER_AZR}.yaml:$(pwd)/config-${CLUSTER_AWS}.yaml"
touch config.yaml
kubectl config set-context z --cluster="${CLUSTER_AZR}" --user="${CLUSTER_AZR}-admin-token"
kubectl config set-context w --cluster="${CLUSTER_AWS}" --user="${CLUSTER_AWS}-admin-token"

echo "KUBECONFIG=${KUBECONFIG}"

echo "KCP_URL=${KCP_URL}"
echo "KCP_USERNAME=${KCP_USERNAME}"

echo "Kublr Cluster Azure: ${SPACE_AZR}:${CLUSTER_AZR}"
echo "Kublr Cluster AWS  : ${SPACE_AWS}:${CLUSTER_AWS}"
