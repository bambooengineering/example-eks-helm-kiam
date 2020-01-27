#!/usr/bin/env bash
set -euo pipefail

STACK_NAME="example-kiam-cluster"

echo "Deleting example cloudformation, helm and kiam stack..."
aws cloudformation delete-stack --stack-name $STACK_NAME

echo "Waiting for the $STACK_NAME stack to finish deleting. This can take some time (~15 minutes)."
aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME

echo "Complete!"
