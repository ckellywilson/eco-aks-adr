#!/bin/bash
set -e

ENV=${1:-dev}

echo "================================"
echo "Deploying Hub to $ENV"
echo "================================"
echo ""

# Initialize Terraform with backend
terraform init -backend-config="backend-$ENV.tfbackend"

# Plan deployment
terraform plan -var-file="$ENV.tfvars" -out=tfplan

# Apply deployment
terraform apply tfplan

# Generate outputs
echo "Generating outputs..."
terraform output -json > "hub-eastus-outputs.json"
echo "✓ Outputs saved to hub-eastus-outputs.json"
echo ""
echo "================================"
echo "✓ Hub deployment complete"
echo "================================"
