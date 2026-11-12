#!/bin/bash
set -e
set -o pipefail

PROJECT_NAME="ResortsLite"
NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')

echo "=== ResortsLite GKE Deployment Script ==="
echo ""

# Ask for GCP cluster details
read -p "Enter GCP Project ID: " GCP_PROJECT
read -p "Enter GCP Zone (e.g., us-central1-a): " GCP_ZONE
read -p "Enter GKE Cluster Name: " CLUSTER_NAME
read -p "Enter Image URI (full path with registry and tag): " IMAGE_URI

echo ""
echo "Configuring kubectl for GKE cluster..."
gcloud container clusters get-credentials "$CLUSTER_NAME" --zone "$GCP_ZONE" --project "$GCP_PROJECT"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to configure kubectl for GKE cluster"
    exit 1
fi

echo ""
echo "Verifying cluster connectivity..."
kubectl cluster-info || exit 1

# Ask for environment variables (non-credential)
echo ""
echo "Enter values for environment variables (press Enter to skip):"
read -p "Enter value for PAYMENT_API_URL (or press Enter to skip): " PAYMENT_API_URL
read -p "Enter value for INVENTORY_API_URL (or press Enter to skip): " INVENTORY_API_URL
read -p "Enter value for NOTIFICATION_API_URL (or press Enter to skip): " NOTIFICATION_API_URL

# Ask for credentials (without echoing)
echo ""
echo "Enter credential values (not echoed):"
read -s -p "Enter DB_HOST: " DB_HOST
echo ""
read -s -p "Enter DB_USER: " DB_USER
echo ""
read -s -p "Enter DB_PASS: " DB_PASS
echo ""
read -s -p "Enter REDIS_HOST: " REDIS_HOST
echo ""
read -s -p "Enter REDIS_PORT: " REDIS_PORT
echo ""

# Create Secret with credentials
echo ""
echo "Creating Kubernetes Secret..."
kubectl create secret generic ${NAME}-secrets -n ${NAME} \
    --from-literal=DB_HOST="$DB_HOST" \
    --from-literal=DB_USER="$DB_USER" \
    --from-literal=DB_PASS="$DB_PASS" \
    --from-literal=REDIS_HOST="$REDIS_HOST" \
    --from-literal=REDIS_PORT="$REDIS_PORT" \
    --dry-run=client -o yaml | kubectl apply -f -

# Apply namespace
echo ""
echo "Applying namespace..."
kubectl apply -f kubernetes/namespace.yaml

# Replace placeholders in deployment.yaml
echo ""
echo "Deploying application..."
sed -i.bak "s|{{IMAGE_URI}}|${IMAGE_URI}|g" kubernetes/deployment.yaml
sed -i.bak "s|{{PAYMENT_API_URL}}|${PAYMENT_API_URL:-http://payment-service:9090/charge}|g" kubernetes/deployment.yaml
sed -i.bak "s|{{INVENTORY_API_URL}}|${INVENTORY_API_URL:-http://inventory-service:8081/rooms}|g" kubernetes/deployment.yaml
sed -i.bak "s|{{NOTIFICATION_API_URL}}|${NOTIFICATION_API_URL:-http://notify-service:7070/send}|g" kubernetes/deployment.yaml
rm -f kubernetes/deployment.yaml.bak

# Apply deployment, service, and ingress
kubectl apply -f kubernetes/deployment.yaml
kubectl apply -f kubernetes/service.yaml
kubectl apply -f kubernetes/ingress.yaml

# Wait for deployment rollout
echo ""
echo "Waiting for deployment rollout..."
kubectl rollout status deployment/${NAME} -n ${NAME}

# Show deployment status
echo ""
echo "=== Deployment Status ==="
kubectl get pods,svc,ingress -n ${NAME}

# Show application URL
echo ""
echo "=== Application URL ==="
echo "http://${NAME}.example.com"

echo ""
echo "=== Deployment complete ==="
echo "To rollback: kubectl rollout undo deployment/${NAME} -n ${NAME}"
