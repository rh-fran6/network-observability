#!/bin/bash

set -eo pipefail

# Define variables
export LOKI_NAMESPACE="loki-netobserve"
export NETOBSERVE_NAMESPACE="network-observability"
export S3_BUCKET="sts-s3-bucket-17042024-demo"
export ROLE_NAME="${CLUSTER_NAME}-demo-loki-s3"
export SA="install-loki-with-sts"
export TRUST_POLICY_FILE="TrustPolicy.json"
export POLICY_NAME="${CLUSTER_NAME}-demo-loki-s3"
export POLICY_FILE="s3Policy.json"
export SCRATCH_DIR="./"
export LOKISTACK_NAMESPACE="loki-stack"
export LOKI_CLUSTER_ADMIN_USER="netobserve-admin-user"
export LOKI_SECRET="loki-s3-secret"
export LOKISTACK_NAME="loki-stack-lokistack"

aws s3 rb s3://$S3_BUCKET --force || true

echo "Please enter Cluster Name:"
read -r CLUSTER_NAME

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

POLICY_NAME="${CLUSTER_NAME}-demo-loki-s3"
ROLE_NAME="${CLUSTER_NAME}-demo-loki-s3"

# Function to print error message and exit
handle_error() {
    echo "An error occurred. Exiting..."
    exit 1
}

# Trap errors and handle them using the handle_error function
trap handle_error ERR

# Grab policy ARN
echo "Retrieving IAM policy ARN..."
POLICY_ARN=$(aws iam list-policies --query "Policies[?PolicyName=='${POLICY_NAME}'].Arn" --output text) || true

if [[ -z "$POLICY_ARN" ]]; then
    echo "Policy $POLICY_NAME not found. "
fi

# Deleting policy files from directory
echo "Deleting json files from local directory..."
rm -rf *.json

# Detach policy from role
echo "Detaching IAM policy from role..."
aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "$POLICY_ARN" || true

# Delete IAM role
echo "Deleting IAM role..."
aws iam delete-role --role-name "$ROLE_NAME" || true

# Delete IAM policy
echo "Deleting IAM policy..."
aws iam delete-policy --policy-arn "$POLICY_ARN" || true

# Deleting secret
echo "Deleting secret..."
oc delete secret $LOKI_SECRET -n $LOKI_NAMESPACE || true

# Deleting secret
echo "Deleting Service Account..."
oc delete serviceaccount $SA -n $LOKI_NAMESPACE || true

# Deleting Group
echo "Deleting group..."
oc delete secret $LOKI_CLUSTER_ADMIN_USER || true

# Delete CRDs
echo "Deleting LokiStack CRD..."
oc delete lokistack $LOKISTACK_NAME -n $LOKI_NAMESPACE || true

# Deleting Cluster Role Bindings
echo "Deleting Cluster Role Bindings..."
for i in $LOKI_CLUSTER_ADMIN_USER-group 'logging-all-application-logs-reader'; do
  oc delete clusterrolebinding $i || true
done


# Install Subscription & CSVs
for i in 'subscription' 'operatorgroup'; do
  oc delete subscription $LUSTER_NAME-loki-operator -n $LOKI_NAMESPACE || true
  oc delete subscription $NETOBSERVE_NAMESPACE-operatorgroup -n $NETOBSERVE_NAMESPACE || true
done

oc delete csv "$(oc get csv -n$LOKI_NAMESPACE | grep loki | awk '{print $1}')" || true

oc delete csv "$(oc get csv -n $NETOBSERVE_NAMESPACE | grep network | awk '{print $1}')" || true

# Delete Projects
for i in $NETOBSERVE_NAMESPACE $LOKI_NAMESPACE; do
  oc delete project "$i" || true
done

clear

# Output success message
echo "Cleanup completed successfully."