#!/usr/bin/env bash
set -euo pipefail

echo "Setting up EKS cluster with cloudformation, helm and kiam..."
echo "AWS region: $AWS_DEFAULT_REGION"
echo "EC2 ssh key name: $KEY_NAME"
echo "Checking helm install"
helm version --client
echo "Checking aws install"
aws --version

# Check the key pair exists
aws ec2 describe-key-pairs --key-name $KEY_NAME

CLUSTER_NAME="example-kiam-cluster"
STACK_NAME=$CLUSTER_NAME
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# This command creates the full environment for the kiam example to run.
# Since it necessarily creates roles, the `--capabilities CAPABILITY_NAMED_IAM` flag
# is required.
echo "Creating cloudformation stack..."
aws cloudformation create-stack  \
    --capabilities CAPABILITY_NAMED_IAM \
    --stack-name $CLUSTER_NAME \
    --parameters ParameterKey=EKSClusterName,ParameterValue=$CLUSTER_NAME ParameterKey=KeyName,ParameterValue=$KEY_NAME \
    --template-body file://cloudformation-vpc-eks-kiam.yaml

echo "Waiting for the $STACK_NAME stack to finish creating. The generation of an EKS cluster can take some time (~15 minutes). You can watch the progress in the AWS console, or why not go and get a coffee?"
aws cloudformation wait stack-create-complete --stack-name $STACK_NAME

echo "Retrieve the connection details for the new cluster..."
aws eks update-kubeconfig --name $CLUSTER_NAME
# Added new context arn:aws:eks:eu-west-1:905282256883:cluster/eks-cloudformation-helm-kiam to /home/username/.kube/config

# Output the roles of the two node groups
NODE_INSTANCE_ROLE=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query 'Stacks[0].Outputs[?OutputKey==`NodeInstanceRole`].OutputValue' --output text)
KIAM_SERVER_NODE_INSTANCE_ROLE=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query 'Stacks[0].Outputs[?OutputKey==`KiamServerNodeInstanceRole`].OutputValue' --output text)

echo "Found node instance role: $NODE_INSTANCE_ROLE"
echo "Found kiam server node instance role: $KIAM_SERVER_NODE_INSTANCE_ROLE"

echo "Ensure that the nodes from the worker groups can join the cluster."
# Note, the file must contain the above node instance role so we insert it before applying the template.
cp templates/aws-auth-cm.yaml /tmp/aws-auth-cm-temp.yaml
sed -i 's@KIAM_SERVER_NODE_INSTANCE_ROLE@'$KIAM_SERVER_NODE_INSTANCE_ROLE'@g' /tmp/aws-auth-cm-temp.yaml
sed -i 's@NODE_INSTANCE_ROLE@'$NODE_INSTANCE_ROLE'@g' /tmp/aws-auth-cm-temp.yaml
kubectl apply -f /tmp/aws-auth-cm-temp.yaml
rm /tmp/aws-auth-cm-temp.yaml

echo "Wait for the nodes to become visible and Ready."
while [ "$(kubectl get nodes | grep -c ' Ready ')" != 2 ]; do echo "$(date): Looking for running nodes..." && sleep 2 ; done

echo "Nodes all found to be Ready."
kubectl get nodes

echo "Allowing add-ons to administer themselves..."
kubectl create clusterrolebinding add-on-cluster-admin --clusterrole=cluster-admin --serviceaccount=kube-system:default

echo "Installing helm..."
helm init --history-max 5 --wait

echo "Preparing kiam-secrets..."
helm upgrade --install kiam-secrets kiam-secrets --namespace kube-system

echo "Installing kiam..."
helm repo update
helm upgrade --install kiam stable/kiam --namespace kube-system --values values.yaml

echo "Creating the example namespace and business logic pods..."
kubectl apply -f templates/example-namespace.yaml
helm upgrade --install example-business-logic example-business-logic --namespace example

echo "**********************************************************"

echo "Complete!"
echo "You can now ssh onto the example business logic pod to check the kiam installation."
echo "See the blog post for more details at https://bambooengineering.io/2019/06/14/kiam-on-eks-with-helm.html"
