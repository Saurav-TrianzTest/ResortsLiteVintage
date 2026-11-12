#!/bin/bash
set -e

echo "=== ResortsLite (RLEKS) Build and Push Script ==="
echo ""

# Ask for registry details
echo "1. Target Platform: AWS ECR"
echo ""
read -p "Enter AWS region (e.g., us-east-1): " AWS_REGION
read -p "Enter ECR repository name: " ECR_REPO
read -p "Enter image tag (leave empty for 'latest'): " IMAGE_TAG

# Set defaults
if [ -z "$IMAGE_TAG" ]; then
    IMAGE_TAG="latest"
fi

# Sanitize names
PROJECT_NAME="ResortsLite"
IMAGE_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')

REGISTRY_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
FULL_IMAGE_NAME="${REGISTRY_URL}/${ECR_REPO}:${IMAGE_TAG}"

echo ""
echo "Image: ${FULL_IMAGE_NAME}"
echo ""

# Get AWS account ID
echo "2. Retrieving AWS account ID..."
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGISTRY_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
FULL_IMAGE_NAME="${REGISTRY_URL}/${ECR_REPO}:${IMAGE_TAG}"

echo "Account ID: ${AWS_ACCOUNT_ID}"
echo "Registry URL: ${REGISTRY_URL}"
echo ""

# Login to ECR
echo "3. Logging in to Amazon ECR..."
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$REGISTRY_URL"
echo "Login successful."
echo ""

# Create repository if it doesn't exist
echo "4. Checking if ECR repository exists..."
if aws ecr describe-repositories --repository-names "$ECR_REPO" --region "$AWS_REGION" >/dev/null 2>&1; then
    echo "Repository '${ECR_REPO}' already exists."
else
    echo "Creating ECR repository '${ECR_REPO}'..."
    aws ecr create-repository --repository-name "$ECR_REPO" --region "$AWS_REGION"
    echo "Repository created."
fi
echo ""

# Build the Docker image
echo "5. Building Docker image..."
docker build -f Dockerfile -t "$FULL_IMAGE_NAME" .
echo "Build complete."
echo ""

# Push the image
echo "6. Pushing image to ECR..."
docker push "$FULL_IMAGE_NAME"
echo "Push complete."
echo ""

echo "=== Done ==="
echo "Image pushed to: ${FULL_IMAGE_NAME}"
