#!/bin/bash
set -e
set -o pipefail

APP_NAME="resortslite"
NAMESPACE="resortslite"

echo "=== Deploy ${APP_NAME} to AWS EKS ==="
read -p "AWS region (e.g. us-east-1): " AWS_REGION
read -p "EKS cluster name: " CLUSTER_NAME
read -p "Docker image URI (registry/repo:tag): " IMAGE_URI
if [ -z "$AWS_REGION" ] || [ -z "$CLUSTER_NAME" ] || [ -z "$IMAGE_URI" ]; then
  echo "AWS region, cluster name and image URI are required"; exit 1
fi

read -p "Enter value for REDIS_HOST (or press Enter to skip) [localhost]: " REDIS_HOST
read -p "Enter value for REDIS_PORT (or press Enter to skip) [6379]: " REDIS_PORT
read -s -p "Enter value for REDIS_PASSWORD (or press Enter to skip): " REDIS_PASSWORD; echo
read -p "Enter value for REDIS_SSL_ENABLED (or press Enter to skip) [false]: " REDIS_SSL_ENABLED
read -p "Enter value for SESSION_REDIS_NAMESPACE (or press Enter to skip) [resortslite:session]: " SESSION_REDIS_NAMESPACE
read -p "Enter value for BOOKING_CACHE_KEY_PREFIX (or press Enter to skip) [resortslite:booking:]: " BOOKING_CACHE_KEY_PREFIX
read -p "Enter value for BOOKING_CACHE_TTL_SECONDS (or press Enter to skip) [3600]: " BOOKING_CACHE_TTL_SECONDS

REDIS_HOST=${REDIS_HOST:-localhost}
REDIS_PORT=${REDIS_PORT:-6379}
REDIS_SSL_ENABLED=${REDIS_SSL_ENABLED:-false}
SESSION_REDIS_NAMESPACE=${SESSION_REDIS_NAMESPACE:-resortslite:session}
BOOKING_CACHE_KEY_PREFIX=${BOOKING_CACHE_KEY_PREFIX:-resortslite:booking:}
BOOKING_CACHE_TTL_SECONDS=${BOOKING_CACHE_TTL_SECONDS:-3600}

# Work on a temp copy so the template manifests keep their placeholders
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
cp -r "$SCRIPT_DIR/../kubernetes" "$WORK_DIR/kubernetes"

for f in "$WORK_DIR"/kubernetes/*.yaml; do
  sed -i 's|{{IMAGE_URI}}|'"$IMAGE_URI"'|g' "$f"
  sed -i 's|{{REDIS_HOST}}|'"$REDIS_HOST"'|g' "$f"
  sed -i 's|{{REDIS_PORT}}|'"$REDIS_PORT"'|g' "$f"
  sed -i 's|{{REDIS_SSL_ENABLED}}|'"$REDIS_SSL_ENABLED"'|g' "$f"
  sed -i 's|{{SESSION_REDIS_NAMESPACE}}|'"$SESSION_REDIS_NAMESPACE"'|g' "$f"
  sed -i 's|{{BOOKING_CACHE_KEY_PREFIX}}|'"$BOOKING_CACHE_KEY_PREFIX"'|g' "$f"
  sed -i 's|{{BOOKING_CACHE_TTL_SECONDS}}|'"$BOOKING_CACHE_TTL_SECONDS"'|g' "$f"
done

echo "Configuring kubectl..."
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

echo "Verifying cluster connectivity..."
kubectl cluster-info || { echo "Cannot connect to cluster"; exit 1; }

echo "Applying manifests..."
kubectl apply -f "$WORK_DIR/kubernetes/namespace.yaml"

kubectl create secret generic resortslite-secrets -n "$NAMESPACE" \
  --from-literal=REDIS_PASSWORD="$REDIS_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f "$WORK_DIR/kubernetes/deployment.yaml"
kubectl apply -f "$WORK_DIR/kubernetes/service.yaml"
kubectl apply -f "$WORK_DIR/kubernetes/ingress.yaml"

echo "Waiting for rollout..."
if ! kubectl rollout status deployment/${APP_NAME} -n ${NAMESPACE} --timeout=300s; then
  echo "Rollout failed. To roll back run:"
  echo "  kubectl rollout undo deployment/${APP_NAME} -n ${NAMESPACE}"
  exit 1
fi

kubectl get pods,svc,ingress -n ${NAMESPACE}

INGRESS_HOST=$(kubectl get ingress ${APP_NAME}-ingress -n ${NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
if [ -n "$INGRESS_HOST" ]; then
  echo "Application URL: http://${INGRESS_HOST}/ (health: http://${INGRESS_HOST}/actuator/health)"
else
  echo "Ingress address not yet assigned. Check: kubectl get ingress -n ${NAMESPACE}"
fi
