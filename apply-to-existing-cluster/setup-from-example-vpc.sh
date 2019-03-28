#!/usr/bin/env bash
set -euo pipefail

# TODO allow this to be overriden
CLUSTER_NAME="eks-cloudformation-helm"

# TODO check jq is installed

echo "Setting up Kiam using Helm..."
ORIGINAL_STACK_NAME=$CLUSTER_NAME

# First we must obtain all the values we need as Paramters to our new stack.
# We could use dependant  TODO stacks here, but keeping everything as environment
#   variables should make it easier for you apply it to your own systems.
ORIGINAL_OUTPUTS=$(aws cloudformation describe-stacks --stack-name $ORIGINAL_STACK_NAME  | jq '.["Stacks"][0]["Outputs"]')

EKS_CLUSTER_NAME=$(echo $ORIGINAL_OUTPUTS | jq '.[] | select(.OutputKey=="EKSClusterName") | .["OutputValue"]')
KEY_NAME=$(echo $ORIGINAL_OUTPUTS | jq '.[] | select(.OutputKey=="KeyName") | .["OutputValue"]')
CONTROL_PLANE_SECURITY_GROUP=$(echo $ORIGINAL_OUTPUTS | jq '.[] | select(.OutputKey=="ControlPlaneSecurityGroup") | .["OutputValue"]')
AMI_ID=$(echo $ORIGINAL_OUTPUTS | jq '.[] | select(.OutputKey=="AMIID") | .["OutputValue"]')
NODE_SECURITY_GROUP=$(echo $ORIGINAL_OUTPUTS | jq '.[] | select(.OutputKey=="NodeSecurityGroup") | .["OutputValue"]')
VPC_ID=$(echo $ORIGINAL_OUTPUTS | jq '.[] | select(.OutputKey=="VpcId") | .["OutputValue"]')
PRIVATE_SUBNET_01=$(echo $ORIGINAL_OUTPUTS | jq '.[] | select(.OutputKey=="PrivateSubnet01") | .["OutputValue"]')
PRIVATE_SUBNET_02=$(echo $ORIGINAL_OUTPUTS | jq '.[] | select(.OutputKey=="PrivateSubnet02") | .["OutputValue"]')
PRIVATE_SUBNET_03=$(echo $ORIGINAL_OUTPUTS | jq '.[] | select(.OutputKey=="PrivateSubnet03") | .["OutputValue"]')

STACK_NAME=$CLUSTER_NAME-kiam-server-nodes

# This command creates the kiam server worker nodes.
# Since it necessarily creates roles, the `--capabilities CAPABILITY_NAMED_IAM` flag is required.
echo "Creating cloudformation stack..."
aws cloudformation create-stack  \
    --capabilities CAPABILITY_NAMED_IAM \
    --stack-name $STACK_NAME \
    --parameters ParameterKey=EKSClusterName,ParameterValue=$EKS_CLUSTER_NAME \
                 ParameterKey=KeyName,ParameterValue=$KEY_NAME \
                 ParameterKey=ControlPlaneSecurityGroup,ParameterValue=$CONTROL_PLANE_SECURITY_GROUP \
                 ParameterKey=AMIID,ParameterValue=$AMI_ID \
                 ParameterKey=NodeSecurityGroup,ParameterValue=$NODE_SECURITY_GROUP \
                 ParameterKey=VPC,ParameterValue=$VPC_ID \
                 ParameterKey=PrivateSubnet01,ParameterValue=$PRIVATE_SUBNET_01 \
                 ParameterKey=PrivateSubnet02,ParameterValue=$PRIVATE_SUBNET_02 \
                 ParameterKey=PrivateSubnet03,ParameterValue=$PRIVATE_SUBNET_03 \
    --template-body file://cloudformation-kiam.yaml

echo "Waiting for the $STACK_NAME stack to finish creating. This should take a couple of minutes..."
aws cloudformation wait stack-create-complete --stack-name $STACK_NAME

echo "Retrieve the connection details for the new cluster..."
aws eks update-kubeconfig --name $CLUSTER_NAME

echo "Retrieving the role of the kiam server node group"
KIAM_SERVER_NODE_INSTANCE_ROLE=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query 'Stacks[0].Outputs[?OutputKey==`KiamServerNodeInstanceRole`].OutputValue' --output text)
echo "Found kiam server node instance role: $KIAM_SERVER_NODE_INSTANCE_ROLE"

echo "Ensure that the nodes from the worker groups can join the cluster by updating the aws-auth ConfigMap."
# See https://eksworkshop.com/codepipeline/configmap/ for what this is doing
ROLE="    - rolearn: $KIAM_SERVER_NODE_INSTANCE_ROLE\n      username: system:node:{{EC2PrivateDNSName}}\n      groups:\n        - system:bootstrappers\n        - system:nodes"
kubectl get -n kube-system configmap/aws-auth -o yaml | awk "/mapRoles: \|/{print;print \"$ROLE\";next}1" > /tmp/aws-auth-patch.yml
kubectl patch configmap/aws-auth -n kube-system --patch "$(cat /tmp/aws-auth-patch.yml)"
kubectl describe configmap aws-auth --namespace kube-system

echo "Wait for the kiam-server nodes to become visible and Ready."
until kubectl get nodes | grep -m 1 " Ready *kiam-server-node"; do echo "$(date): Looking for running nodes by node role 'kiam-server-node'..." && sleep 2 ; done

echo "Node found to be Ready."
kubectl get nodes

echo "Installing kiam..."
helm upgrade --install stable/kiam kiam --namespace kube-system

echo "Creating the example namespace and business logic..."
kubectl apply -f templates/namespace.yaml
helm upgrade --install example-business-logic example-business-logic --namespace example
