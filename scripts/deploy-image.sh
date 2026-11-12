#!/bin/bash
set -e
set -o pipefail

echo "=== ResortsLite Deploy to Azure AKS Script ==="

NAMESPACE="resortslite"

# Ask for Azure cluster details
read -p "Enter Azure resource group: " RESOURCE_GROUP
read -p "Enter AKS cluster name: " CLUSTER_NAME

echo ""
echo "Configuring kubectl for AKS cluster: $CLUSTER_NAME"
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to configure kubectl"
    exit 1
fi

echo ""
echo "Checking cluster connectivity..."
kubectl cluster-info
if [ $? -ne 0 ]; then
    echo "ERROR: Cannot connect to AKS cluster"
    exit 1
fi

# Ask for image URI
read -p "Enter full image URI (e.g., myacr.azurecr.io/resortslite:latest): " IMAGE_URI

# Ask for environment variables
echo ""
read -p "Enter value for REDIS_HOST (or press Enter to skip): " REDIS_HOST
read -p "Enter value for PAYMENT_API (or press Enter to skip): " PAYMENT_API

# Ask for credentials (without echoing)
echo ""
read -s -p "Enter value for REDIS_PASSWORD (or press Enter to skip): " REDIS_PASSWORD
echo ""

# Apply namespace
echo ""
echo "Applying namespace..."
kubectl apply -f kubernetes/namespace.yaml

# Create Secret for credentials
echo ""
echo "Creating Kubernetes Secret..."
kubectl create secret generic resortslite-secrets -n "$NAMESPACE" \
    --from-literal=REDIS_PASSWORD="$REDIS_PASSWORD" \
    --dry-run=client -o yaml | kubectl apply -f -

# Replace placeholders in deployment.yaml
echo ""
echo "Deploying application..."

# Create a temporary copy for substitution
cp kubernetes/deployment.yaml "$JOB_WORK_DIR/deployment-substituted.yaml"

sed -i.bak "s|{{NAMESPACE}}|$NAMESPACE|g" "$JOB_WORK_DIR/deployment-substituted.yaml"
sed -i.bak "s|{{IMAGE_URI}}|$IMAGE_URI|g" "$JOB_WORK_DIR/deployment-substituted.yaml"
sed -i.bak "s|{{REDIS_HOST}}|$REDIS_HOST|g" "$JOB_WORK_DIR/deployment-substituted.yaml"
sed -i.bak "s|{{PAYMENT_API}}|$PAYMENT_API|g" "$JOB_WORK_DIR/deployment-substituted.yaml"
rm -f "$JOB_WORK_DIR/deployment-substituted.yaml.bak"

kubectl apply -f "$JOB_WORK_DIR/deployment-substituted.yaml"
rm -f "$JOB_WORK_DIR/deployment-substituted.yaml"

# Apply service and ingress with namespace substitution
cp kubernetes/service.yaml "$JOB_WORK_DIR/service-substituted.yaml"
sed -i.bak "s|{{NAMESPACE}}|$NAMESPACE|g" "$JOB_WORK_DIR/service-substituted.yaml"
rm -f "$JOB_WORK_DIR/service-substituted.yaml.bak"
kubectl apply -f "$JOB_WORK_DIR/service-substituted.yaml"
rm -f "$JOB_WORK_DIR/service-substituted.yaml"

cp kubernetes/ingress.yaml "$JOB_WORK_DIR/ingress-substituted.yaml"
sed -i.bak "s|{{NAMESPACE}}|$NAMESPACE|g" "$JOB_WORK_DIR/ingress-substituted.yaml"
rm -f "$JOB_WORK_DIR/ingress-substituted.yaml.bak"
kubectl apply -f "$JOB_WORK_DIR/ingress-substituted.yaml"
rm -f "$JOB_WORK_DIR/ingress-substituted.yaml"

# Wait for deployment
echo ""
echo "Waiting for deployment to be ready..."
kubectl rollout status deployment/resortslite -n "$NAMESPACE"
if [ $? -ne 0 ]; then
    echo "ERROR: Deployment failed"
    echo "Rollback with: kubectl rollout undo deployment/resortslite -n $NAMESPACE"
    exit 1
fi

# Show status
echo ""
echo "=== Deployment complete ==="
kubectl get pods,svc,ingress -n "$NAMESPACE"
echo ""
echo "Application URL: https://resortslite.example.com"
echo ""
echo "If something went wrong, rollback with:"
echo "  kubectl rollout undo deployment/resortslite -n $NAMESPACE"
