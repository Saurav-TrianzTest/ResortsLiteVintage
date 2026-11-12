#!/bin/bash
set -e
set -o pipefail

echo "=== ResortsLite Build and Push Script ==="

# Project name
PROJECT_NAME="ResortsLite"

# Sanitize project name for image name
IMAGE_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')

# Ask for registry choice
echo ""
echo "Choose target registry:"
echo "  1) Azure ACR"
echo "  2) Docker Hub"
read -p "Enter choice (1 or 2): " REGISTRY_CHOICE

if [ "$REGISTRY_CHOICE" = "1" ]; then
    # Azure ACR
    read -p "Enter ACR name (e.g., myacr): " ACR_NAME
    read -p "Enter image tag (press Enter for 'latest'): " IMAGE_TAG
    if [ -z "$IMAGE_TAG" ]; then
        IMAGE_TAG="latest"
    fi
    FULL_IMAGE_NAME="${ACR_NAME}.azurecr.io/${IMAGE_NAME}:${IMAGE_TAG}"
    echo ""
    echo "Logging in to Azure ACR: $ACR_NAME"
    az acr login --name "$ACR_NAME"
    if [ $? -ne 0 ]; then
        echo "ERROR: ACR login failed"
        exit 1
    fi
elif [ "$REGISTRY_CHOICE" = "2" ]; then
    # Docker Hub
    read -p "Enter Docker Hub username: " DOCKER_USERNAME
    read -s -p "Enter Docker Hub password: " DOCKER_PASSWORD
    echo ""
    read -p "Enter image tag (press Enter for 'latest'): " IMAGE_TAG
    if [ -z "$IMAGE_TAG" ]; then
        IMAGE_TAG="latest"
    fi
    FULL_IMAGE_NAME="${DOCKER_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}"
    echo ""
    echo "Logging in to Docker Hub"
    echo "$DOCKER_PASSWORD" | docker login --username "$DOCKER_USERNAME" --password-stdin
    if [ $? -ne 0 ]; then
        echo "ERROR: Docker Hub login failed"
        exit 1
    fi
else
    echo "ERROR: Invalid choice"
    exit 1
fi

echo ""
echo "Building image: $FULL_IMAGE_NAME"
docker build -f Dockerfile -t "$FULL_IMAGE_NAME" .
if [ $? -ne 0 ]; then
    echo "ERROR: Docker build failed"
    exit 1
fi

echo ""
echo "Pushing image: $FULL_IMAGE_NAME"
docker push "$FULL_IMAGE_NAME"
if [ $? -ne 0 ]; then
    echo "ERROR: Docker push failed"
    exit 1
fi

echo ""
echo "=== Build and push complete ==="
echo "Image: $FULL_IMAGE_NAME"
