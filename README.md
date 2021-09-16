# TOC

* 1 Pre-requisites
* 1.1 Setup environment
* 1.2 Create Azure and AWS clusters and setup local kubectl
* 2 Prepate Strimzi / Kafka
* 2.1 Deploy Strimzi and Kafka
* 2.2 Install Grafana dashboards
* 2.3 Simple consumer and producer
* 3 Prepate ArgoCD projects and environment
* 3.1 Install ArgoCD CLI
* 3.1 Deploy ArgoCD and Test App
* 3.3 Connect to ArgoCD
* 3.4 Deploy a test app
* 4 Prepare Velero Backup
* 4.1 Azure
* 4.1.1 Create Backups Azure Storage Account and Resource Group
* 4.1.2 Deploy Velero Server to Azure cluster
* 4.2 AWS
* 4.2.1 Create Backup AWS S3 bucket
* 4.1.2 Deploy Velero Server to Azure cluster
* 5 Backup
* 5.1 One-time Backup Kafka
* 5.2 Scheduled Backup Kafka
* 5.3 Backup ArgoCD and App
* 6 Restore
* 6.1 Restore Kafka
* 6.1.1 Delete Kafka
* 6.1.2 Restore Kafka
* 6.2 Restore ArgoCD and/or Application
* 6.2.1 Delete App Namespace
* 6.2.2 Delete ArgoCD namespace
* 6.2.3 Restore ArgoCD Namespace
* 6.2.4 Restore App Namespace
* 7 Cleanup

# 1. Pre-requisites

* Kublr 1.21.0+
* Kubernetes 1.20+
* Azure account
* AWS account
* kubectl 1.19+
* Helm v3.5+
* Docker 20.10.5+
* Bash
* jq v1.6+

## 1.1. Setup environment

Clone the project:

```bash
git clone git@github.com:kublr/bcdr-demo.git
```

Specify KCP connection parameters:

```bash
export KCP_URL=...
export KCP_USERNAME=...
export KCP_PASSWORD=...

export AZURE_BACKUP_RESOURCE_GROUP=velero_backups_test

export AZURE_STORAGE_ACCOUNT_ID="myvelerosa326492368217"

# Azure API Connection Credentials
export AZURE_SUBSCRIPTION_ID=...
export AZURE_TENANT_ID=...
export AZURE_CLIENT_ID=...
export AZURE_CLIENT_SECRET=...

# AWS

export AWS_BUCKET=my-bcdr-demo-bucket
export AWS_REGION=us-east-1

export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...

```

Set environment variables:

```bash
. bcdr-demo/hacks/00-prep-env.sh
```

Make sure that `azure` Azure credentials, `ssh-pub` public SSH key, and `aws` AWS credentials secrets
exist in the `default` space in the KCP.

## 1.2. Create Azure and AWS clusters and setup local kubectl

Create clusters:

```bash
. bcdr-demo/hacks/11-create-kublr-cluster-azr.sh
. bcdr-demo/hacks/12-create-kublr-cluster-aws.sh
```

When the cluster is created download and setup kubeconfig:

```bash
. bcdr-demo/hacks/15-get-kubeconfigs.sh
```

Verify that it works:

```bash
kubectl get nodes --context=z
kubectl get nodes --context=w
```

# 2. Prepate Strimzi / Kafka

## 2.1. Deploy Strimzi and Kafka

Deploy/update strimzi operator to AWS and Azure clusters (use `kubectl config use-context w` and
`kubectl config use-context z` to switch):

```bash
kubectl create ns kafka

helm upgrade --install --create-namespace \
    -n strimzi \
    strimzi-kafka-operator \
    https://github.com/strimzi/strimzi-kafka-operator/releases/download/0.22.1/strimzi-kafka-operator-helm-3-chart-0.22.1.tgz \
    --set "watchNamespaces[0]=kafka"
```

Deploy/update kafka clusters:

```bash
kubectl apply -f bcdr-demo/template-kafka/
```

## 2.2. Install Grafana dashboards

Import Grafana dashboards from `grafana-dashboards` via Grafana UI.

The dashboards are based on https://github.com/strimzi/strimzi-kafka-operator/tree/master/examples/metrics/grafana-dashboards.
The dashboard are adjusted for Kublr multi-cluster monitoring label schema. The file `grafana-dashboards/adjustments.md` describes
generic adjustments that need to be made for that.

Kafka, Zookeeper, Kafka Exporter metrics are currently configured to be scraped by Prometheus and can be displayed.

## 2.3. Simple consumer and producer

The following command can be used to produce some messages so that kafka data disks are not empty:

```shell
kubectl -n kafka run kafka-producer -ti --image=quay.io/strimzi/kafka:0.21.1-kafka-2.7.0 --rm=true --restart=Never --overrides='{
  "spec": {
    "containers": [{
      "name": "kafka-producer",
      "image": "quay.io/strimzi/kafka:0.21.1-kafka-2.7.0",
      "command": ["bin/kafka-console-producer.sh"],
      "args": [
        "--bootstrap-server", "kafka-cluster-kafka-bootstrap:9092",
        "--topic", "topic-1",
        "--producer-property", "security.protocol=SASL_PLAINTEXT",
        "--producer-property", "sasl.mechanism=SCRAM-SHA-512",
        "--producer-property", "sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username=\"admin\" password=\"admin\";"
      ],
      "stdin": true,
      "tty": true
    }]
  }
}
' -- bash
```

The following command can be used to verify that the messages produced can be consumed.

The same command can be used to verify backup restoration correctness.

```shell
kubectl -n kafka run kafka-consumer -ti --image=quay.io/strimzi/kafka:0.21.1-kafka-2.7.0 --rm=true --restart=Never --overrides='{
  "spec": {
    "containers": [{
      "name": "kafka-consumer",
      "image": "quay.io/strimzi/kafka:0.21.1-kafka-2.7.0",
      "command": ["bin/kafka-console-consumer.sh"],
      "args": [
        "--bootstrap-server", "kafka-cluster-kafka-bootstrap:9092",
        "--topic", "topic-1",
        "--from-beginning",
        "--consumer-property", "security.protocol=SASL_PLAINTEXT",
        "--consumer-property", "sasl.mechanism=SCRAM-SHA-512",
        "--consumer-property", "sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username=\"admin\" password=\"admin\";"
      ],
      "stdin": true,
      "tty": true
    }]
  }
}
' -- bash
```

The producers will wait for input from the terminal.

The consumers will print to the standard output.

`Ctrl-D` will complete the producer, and `Ctrl-C` will complete both producers and consumers.

Cleanup leftover pods:

```shell
kubectl -n kafka delete pod kafka-producer --now
kubectl -n kafka delete pod kafka-consumer --now
```

# 3. Prepate ArgoCD projects and environment

## 3.1. Install ArgoCD CLI

```bash
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/download/v2.0.3/argocd-linux-amd64
chmod +x argocd
```

## 3.1. Deploy ArgoCD and Test App

Perform the following steps for each cluster - AWS and Azure (`kubectl config use-context w`, `kubectl config use-context z`).

```bash
kubectl --context=w create namespace argocd
kubectl --context=w apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.0.3/manifests/install.yaml

kubectl --context=z create namespace argocd
kubectl --context=z apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.0.3/manifests/install.yaml
```

## 3.3. Connect to ArgoCD

Port forward ArgoCD UI:

```bash
kubectl --context=w port-forward svc/argocd-server -n argocd 8081:443 --address 0.0.0.0 > /dev/null 2> /dev/null &
kubectl --context=z port-forward svc/argocd-server -n argocd 8082:443 --address 0.0.0.0 > /dev/null 2> /dev/null &
```

Get password(s):

```bash
echo "ArgoCD pwd AWS  : $(kubectl --context=w -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)"
echo "ArgoCD pwd Azure: $(kubectl --context=z -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)"
```

Login in browser https://localhost:8081 and https://localhost:8082

Login ArgoCD CLI:

```bash
argocd login --name w localhost:8081
argocd login --name z localhost:8082
```

## 3.4. Deploy a test app

Deploy a guestbook app as described in
https://argo-cd.readthedocs.io/en/stable/getting_started/#6-create-an-application-from-a-git-repository
to `guestbook` namespace (mark "autocreate namespace" on sync).

Deploying via CLI in each cluster, switch between cluster with `argocd context w` and `argocd context z`:

```shell
argocd app create guestbook \
   --repo https://github.com/argoproj/argocd-example-apps.git \
   --path guestbook \
   --dest-server https://kubernetes.default.svc \
   --dest-namespace guestbook \
   --sync-option CreateNamespace=true

argocd app sync guestbook
```

# 4. Prepare Velero Backup

## 4.1. Azure

### 4.1.1. Create Backups Azure Storage Account and Resource Group

The following script creates a geo-replicated, HTTPS-only, priivate, and encrypted storage account

```shell
# Resource Group

az group create -n "${AZURE_BACKUP_RESOURCE_GROUP}" --location eastus

# Storage Account

az storage account create \
    --name "${AZURE_STORAGE_ACCOUNT_ID}" \
    --resource-group "${AZURE_BACKUP_RESOURCE_GROUP}" \
    --sku Standard_GRS \
    --https-only true \
    --allow-blob-public-access false \
    --access-tier Hot

# Container

az storage container create \
    --name "${BLOB_CONTAINER}" \
    --public-access off \
    --account-name "${AZURE_STORAGE_ACCOUNT_ID}"
```

### 4.1.2. Deploy Velero Server to Azure cluster

Deploy Velero Server

```shell
kubectl config use-context z

helm upgrade velero https://github.com/vmware-tanzu/helm-charts/releases/download/velero-2.21.0/velero-2.21.0.tgz \
    --install \
    --create-namespace \
    --namespace velero \
\
    --set initContainers[0].name=velero-plugin-for-microsoft-azure \
    --set initContainers[0].image=velero/velero-plugin-for-microsoft-azure:v1.2.0 \
    --set initContainers[0].volumeMounts[0].mountPath=/target \
    --set initContainers[0].volumeMounts[0].name=plugins \
\
    --set configuration.provider=azure \
\
    --set configuration.backupStorageLocation.name=default \
    --set configuration.backupStorageLocation.bucket="${BLOB_CONTAINER}" \
    --set configuration.backupStorageLocation.config.resourceGroup="${AZURE_BACKUP_RESOURCE_GROUP}" \
    --set configuration.backupStorageLocation.config.storageAccount="${AZURE_STORAGE_ACCOUNT_ID}" \
\
    --set configuration.volumeSnapshotLocation.name=default \
    --set configuration.volumeSnapshotLocation.config.resourceGroup="${AZURE_BACKUP_RESOURCE_GROUP}" \
\
    --set credentials.secretContents.cloud="AZURE_CLOUD_NAME=AzurePublicCloud
AZURE_SUBSCRIPTION_ID=${AZURE_SUBSCRIPTION_ID}
AZURE_TENANT_ID=${AZURE_TENANT_ID}
AZURE_CLIENT_ID=${AZURE_CLIENT_ID}
AZURE_CLIENT_SECRET=${AZURE_CLIENT_SECRET}
AZURE_RESOURCE_GROUP=${CLUSTER_AZR}
"
```

Optionally (potentially) multiple additional plugins may be configured in the installation configuration.

Optionally (potentially) multiple additional backup storage locations and volume snapshot locations may be
configured in the installation configuration and/or as CRD objects at runtime via `kubectl`, `velero` CLI,
or other methods.

## 4.2. AWS

### 4.2.1. Create Backup AWS S3 bucket

```shell
aws s3api create-bucket \
    --bucket "${AWS_BUCKET}" \
    --region "${AWS_REGION}"
```

### 4.1.2. Deploy Velero Server to Azure cluster

Deploy Velero Server

```shell
kubectl config use-context w

helm upgrade velero https://github.com/vmware-tanzu/helm-charts/releases/download/velero-2.21.0/velero-2.21.0.tgz \
    --install \
    --create-namespace \
    --namespace velero \
\
    --set initContainers[0].name=velero-plugin-for-aws \
    --set initContainers[0].image=velero/velero-plugin-for-aws:v1.2.0 \
    --set initContainers[0].volumeMounts[0].mountPath=/target \
    --set initContainers[0].volumeMounts[0].name=plugins \
\
    --set configuration.provider=aws \
\
    --set configuration.backupStorageLocation.name=default \
    --set configuration.backupStorageLocation.bucket="${AWS_BUCKET}" \
    --set configuration.backupStorageLocation.config.region="${AWS_REGION}" \
\
    --set configuration.volumeSnapshotLocation.name=default \
    --set configuration.volumeSnapshotLocation.config.region="${AWS_REGION}" \
\
    --set credentials.secretContents.cloud="[default]
aws_access_key_id=${AWS_ACCESS_KEY_ID}
aws_secret_access_key=${AWS_SECRET_ACCESS_KEY}
"
```

Optionally (potentially) multiple additional plugins may be configured in the installation configuration.

Optionally (potentially) multiple additional backup storage locations and volume snapshot locations may be
configured in the installation configuration and/or as CRD objects at runtime via `kubectl`, `velero` CLI,
or other methods.

# 5. Backup

The following steps are exactly the same in AWS and Azure clusters; switch between them with
`kubectl config use-context z` and `kubectl config use-context w`

## 5.1. One-time Backup Kafka

See [velero backup reference](https://velero.io/docs/v1.6/backup-reference/) for more details.

```shell
velero backup create kafka-backup1 --include-namespaces kafka

velero backup get kafka-backup1
velero backup describe kafka-backup1
velero backup describe kafka-backup1 --details
velero backup logs kafka-backup1
```

## 5.2. Scheduled Backup Kafka

```shell
# Schedule backup every 6 hours
velero schedule create kafka --schedule="0 */6 * * *" --include-namespaces kafka
velero schedule get kafka
velero backup get
```

## 5.3. Backup ArgoCD and App

```
velero backup create argo-backup1 --include-namespaces argocd,guestbook

velero backup get argo-backup1
velero backup describe argo-backup1
velero backup describe argo-backup1 --details
velero backup logs argo-backup1
```

# 6. Restore

## 6.1. Restore Kafka

See [Velero restore reference](https://velero.io/docs/v1.6/restore-reference/) for more details.

### 6.1.1. Delete Kafka

```shell
kubectl delete ns kafka
```
### 6.1.2. Restore Kafka

Restore the namespace from backup or schedule:

```shell
velero restore create kafka-restore1 --from-backup kafka-backup1
# OR
velero restore create kafka-restore1 --from-schedule kafka

velero restore get kafka-restore1
velero restore describe kafka-restore1
velero restore describe kafka-restore1 --details
velero restore logs kafka-restore1
```

## 6.2. Restore ArgoCD and/or Application

### 6.2.1. Delete App Namespace

```
kubectl delete ns guestbook
```

ArgoCD shows "missing" application status

### 6.2.2. Delete ArgoCD namespace

```
kubectl delete ns argocd
```

ArgoCD is unavailable.

### 6.2.3. Restore ArgoCD Namespace

```
velero restore create argocd-restore1 --from-backup argo-backup1 --include-namespaces argocd

velero restore get argocd-restore1
velero restore describe argocd-restore1
velero restore describe argocd-restore1 --details
velero restore logs argocd-restore1
```

If necessary restart port forwarding:
```shell
kubectl --context=w port-forward svc/argocd-server -n argocd 8080:443 --address 0.0.0.0 > /dev/null 2> /dev/null &
kubectl --context=z port-forward svc/argocd-server -n argocd 8081:443 --address 0.0.0.0 > /dev/null 2> /dev/null &
```

ArgoCD running, shows "missing" application status

### 6.2.4. Restore App Namespace

```
velero restore create argocd-app-restore1 --from-backup argo-backup1 --include-namespaces guestbook

velero restore get argocd-app-restore1
velero restore describe argocd-app-restore1
velero restore describe argocd-app-restore1 --details
velero restore logs argocd-app-restore1
```

ArgoCD shows healthy synced application status again

# 7. Cleanup

Delete all restore and backup objects and resources:

```shell
velero restore delete --all
velero backup delete --all
```

Wait for all backups to be deleted, checking with the command `velero backup get`.

Delete Velero, ArgoCD and the test app:

```shell
# Veleeo
helm uninstall velero --namespace velero
kubectl delete ns velero
kubectl delete $(kubectl get crd -o name | grep velero)

# ArgoCD and test app
kubectl delete ns guestbook
kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.0.3/manifests/install.yaml
kubectl delete ns argocd
kubectl delete $(kubectl get crd -o name | grep argoproj)
```

Delete Kafaka cluster.

```shell
# Kafka and Strimzi
kubectl delete -f bcdr-demo/template-kafka/
```

Wait for kafka cluster to be deleted.

Delete strimzi operator.

```shell
helm uninstall -n strimzi strimzi-kafka-operator
kubectl delete ns kafka strimzi
kubectl delete $(kubectl get crd -o name | grep 'strimzi\|kafka')
```
