#!/bin/bash

set -eo pipefail

export LOKI_NAMESPACE="loki-netobserve"
export NETOBSERVE_NAMESPACE="network-observability"
export S3_BUCKET="sts-s3-bucket-17042024-demo"
export SA="install-loki-with-sts"
export TRUST_POLICY_FILE="TrustPolicy.json"
export POLICY_FILE="s3Policy.json"
export SCRATCH_DIR="./"
export LOKI_STORAGE_CLASS="gp3"
export LOKI_CLUSTER_ADMIN_USER="admin-user"
export ADMIN_GROUP="cluster-admin"

export LOKI_SECRET="loki-s3-secret"
export LOKISTACK_NAME="loki-stack-lokistack"

# Function to prompt user for input with a message
prompt_user() {
    read -rp "$1: " "$2"
}

# Function to extract AWS account ID
get_account_id() {
    aws sts get-caller-identity --query Account --output text
}

# Function to extract AWS region
get_aws_region() {
    aws configure get region
}

# Function to extract OIDC Provider endpoint
get_oidc_provider_endpoint() {
    rosa describe cluster -c "$(oc get clusterversion -o jsonpath='{.items[].spec.clusterID}{"\n"}')" -o yaml | awk '/oidc_endpoint_url/ {print $2}' | cut -d '/' -f 3,4
}

# Function to create IAM role
create_iam_role() {
    local a="$1"
    aws iam create-role --role-name "$a-demo-loki-s3" --assume-role-policy-document file://$TRUST_POLICY_FILE --query "Role.Arn" --output text
}

# Function to create IAM policy
create_iam_policy() {
    local a=$1
    aws iam create-policy --policy-name "$a-demo-loki-s3" --policy-document file://$POLICY_FILE --query 'Policy.Arn' --output text
}

# Function to attach IAM policy to role
attach_policy_to_role() {
    local a=$1
    local b=$2
    aws iam attach-role-policy --role-name $a --policy-arn $b
}

prompt_user "Please enter Cluster Name" CLUSTER_NAME

# Display variables

ROLE_NAME=$CLUSTER_NAME-demo-loki-s3

POLICY_NAME=$CLUSTER_NAME-demo-loki-s3


echo ROLE NAME: $CLUSTER_NAME-demo-loki-s3

echo POLICY NAME: $CLUSTER_NAME-demo-loki-s3

echo LOKISTACK NAME: $LOKISTACK_NAME

echo ROLE NAME: $CLUSTER_NAME-demo-loki-s3

echo POLICY_NAME: $CLUSTER_NAME-demo-loki-s3

# Extract Account ID
AWS_ACCOUNT_ID=$(get_account_id)
# Extract AWSRegion
AWS_REGION=$(get_aws_region)

# Extract OIDC Provider endpoint
OIDC_PROVIDER_ENDPOINT=$(get_oidc_provider_endpoint)
echo "OIDC Provider Endpoint: $OIDC_PROVIDER_ENDPOINT"

# Create S3 bucket
echo "Creating S3 Bucket $S3_BUCKET..."
aws s3 mb s3://$S3_BUCKET --region $REGION 


# # Retrieve the bucket location
location=$(aws s3api get-bucket-location --bucket $S3_BUCKET --output text)

# Construct the bucket endpoint URL
if [ "$location" = "None" ]; then
    ENDPOINT="https://$S3_BUCKET.s3.amazonaws.com"
else
    ENDPOINT="https://$S3_BUCKET.s3-$AWS_REGION.amazonaws.com"
fi

echo "S3 Endpoint is $ENDPOINT..."

#"s3:ListBucket",
# Create IAM policy
echo "Creating policy file $POLICY_FILE in local directory..."
cat <<EOF > "${SCRATCH_DIR}/$POLICY_FILE"
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListObjects", 
                "s3:ListBucket",
                "s3:GetObject",
                "s3:DeleteObject",
                "s3:PutObject",
                "s3:PutObjectAcl"
            ],
            "Resource": [
                "arn:aws:s3:::$S3_BUCKET/*",
                "arn:aws:s3:::$S3_BUCKET"
            ]
        }
    ]
}
EOF

# Create IAM role
echo "Creating trust policy $TRUST_POLICY_FILE file in local directory..."
cat <<EOF > "${SCRATCH_DIR}/$TRUST_POLICY_FILE"
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER_ENDPOINT}"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "${OIDC_PROVIDER_ENDPOINT}:sub": [
                        "system:serviceaccount:${LOKI_NAMESPACE}:${LOKISTACK_NAME}"
                    ]
                }
            }
        }
    ]
}
EOF

# Create IAM Role 
echo "Creating IAM ROLE ${CLUSTER_NAME}-demo-loki-s3 ..."
ROLE_ARN=$(create_iam_role "$CLUSTER_NAME")
echo "Role ARN: $ROLE_ARN"

# Create IAM Policy
echo "Creating Trust Policy $POLICY_NAME..."
POLICY_ARN=$(create_iam_policy "$CLUSTER_NAME")
echo "Policy ARN: $POLICY_ARN"

# Attach IAM Role to Policy
echo "Attaching ${CLUSTER_NAME}-demo-loki-s3 to $POLICY_NAME..."
attach_policy_to_role "$ROLE_NAME" "$POLICY_ARN"

echo Successfully attached!

# Create namespaces
echo "Creating $LOKI_NAMESPACE and $NETOBSERVE_NAMESPACE Namespaces..."
for ns in "$LOKI_NAMESPACE" "$NETOBSERVE_NAMESPACE"; do
  oc new-project $ns
done

# # Create Secret
echo "Creating Secret $LOKI_SECRET..."
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
#   annotations:
#     eks.amazonaws.com/role-arn: $ROLE_ARN
  name: $LOKI_SECRET
  namespace: $LOKI_NAMESPACE  
stringData:
  bucketnames: $S3_BUCKET
  endpoint: $ENDPOINT
  region: $REGION
  role_arn: $ROLE_ARN
EOF

# Create OperatorGroup
echo "Creating Loki Operator Group called ${CLUSTER_NAME}-loki-operator..."
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: "${CLUSTER_NAME}-loki-operator"
  namespace: $LOKI_NAMESPACE
EOF

# Create Subscription
echo "Creating Loki Subscription called ${CLUSTER_NAME}-loki-operator..."
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: "${CLUSTER_NAME}-loki-operator"
  namespace: $LOKI_NAMESPACE
spec:
  channel: "stable-5.9"
  installPlanApproval: Automatic
  name: loki-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  config:
    env:
    - name: ROLEARN
      value: $ROLE_ARN
EOF

sleep 90

# Create Group
echo "Creating New User Group..."
cat <<EOF | oc apply -f -
apiVersion: user.openshift.io/v1
kind: Group
metadata:
  name: $LOKI_CLUSTER_ADMIN_USER
users:
- admin-user
EOF

# Create ClusterRoleBindings
echo "Creating Cluster Groups..."
cat <<EOF | oc apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: $ADMIN_GROUP
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: $LOKI_CLUSTER_ADMIN_USER
EOF

# Create LokiStack
echo "Creating Lokistack $LOKISTACK_NAME..."
cat <<EOF | oc apply -f -
apiVersion: loki.grafana.com/v1
kind: LokiStack
metadata:
  name: $LOKISTACK_NAME
  namespace: $LOKI_NAMESPACE
spec:
  limits:
    global: 
      retention: 
        days: 20
        streams:
        - days: 4
          priority: 1
          selector: '{kubernetes_namespace_name=~"test.+"}' 
        - days: 1
          priority: 1
          selector: '{log_type="infrastructure"}'
      ingestion:
        ingestionBurstSize: 40
        ingestionRate: 20
        maxGlobalStreamsPerTenant: 25000
      queries:
        maxChunksPerQuery: 2000000
        maxEntriesLimitPerQuery: 10000
        maxQuerySeries: 3000
        queryTimeout: 3m
  size: 1x.small 
  managementState: Managed
  replicationFactor: 1 
  storage:
    schemas:
    - effectiveDate: "2023-10-15"
      version: v13
    secret:
      name: $LOKI_SECRET
      type: s3
      credentialMode: token
  storageClassName: $LOKI_STORAGE_CLASS
  tenants:
    mode: openshift-network
EOF

# Create Subscription for Network Observability
echo "Creating Network Observability Subscription called $NETOBSERVE_NAMESPACE-operatorgroup..."
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: $NETOBSERVE_NAMESPACE-operatorgroup
  namespace: $NETOBSERVE_NAMESPACE
spec:
  channel: stable
  installPlanApproval: Automatic
  name: netobserv-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

# Create OperatorGroup for Network Observability
echo "Creating Network Observability Operator Group called $NETOBSERVE_NAMESPACE-operatorgroup..."
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: $NETOBSERVE_NAMESPACE-operatorgroup
  namespace: $NETOBSERVE_NAMESPACE
spec:
  upgradeStrategy: Default
EOF

sleep 60

# Create Flow Collector CRD
echo "Creating Network Observability FlowCollector CRD..."
cat <<EOF | oc apply -f -
apiVersion: flows.netobserv.io/v1beta2
kind: FlowCollector
metadata:
  name: cluster
spec:
  namespace: $NETOBSERVE_NAMESPACE
  deploymentModel: Direct
  agent:
    type: eBPF                                
    ebpf:
      sampling: 50             ## For DNS Tracking, set to 1 for more accurate reporting               
      logLevel: info
      privileged: true
      resources:
        requests:
          memory: 50Mi
          cpu: 100m
        limits:
          memory: 800Mi
      features:
      - PacketDrop
      - DNSTracking
      - FlowRTT
  processor:               
    logLevel: info
    resources:
      requests:
        memory: 100Mi
        cpu: 100m
      limits:
        memory: 800Mi
    logTypes: Flows
    advanced:
      conversationEndTimeout: 10s
      conversationHeartbeatInterval: 30s
  loki:                     
    mode: LokiStack  
    lokiStack:
      name: $LOKISTACK_NAME
      namespace: $LOKI_NAMESPACE       
  consolePlugin:
    register: true
    logLevel: info
    portNaming:
      enable: true
      portNames:
        "3100": loki
    quickFilters:            
    - name: Applications
      filter:
        src_namespace!: 'openshift-,$LOKI_NAMESPACE'
        dst_namespace!: 'openshift-,$LOKI_NAMESPACE'
      default: true
    - name: Infrastructure
      filter:
        src_namespace: 'openshift-,$LOKI_NAMESPACE'
        dst_namespace: 'openshift-,$LOKI_NAMESPACE'
    - name: Pods network
      filter:
        src_kind: 'Pod'
        dst_kind: 'Pod'
      default: true
    - name: Services network
      filter:
        dst_kind: 'Service'
EOF

# Output success message
echo "Install completed successfully."
