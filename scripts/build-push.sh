#!/bin/bash
set -e
set -o pipefail

PROJECT_NAME="ResortsLite"

echo "=== ResortsLite Build and Push Script ==="
echo ""

# Ask for target platform
echo "Select target platform:"
echo "1. Google Artifact Registry (GCP)"
echo "2. Docker Hub"
read -p "Enter choice (1 or 2): " PLATFORM_CHOICE

IMAGE_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')

if [ "$PLATFORM_CHOICE" = "1" ]; then
    echo ""
    echo "--- Google Artifact Registry ---"
    read -p "Enter GCP Region (e.g., us-central1): " GCP_REGION
    read -p "Enter GCP Project ID: " GCP_PROJECT
    read -p "Enter Artifact Registry Repository Name: " GCP_REPO
    read -p "Enter IMAGE_TAG (press Enter for latest): " IMAGE_TAG

    if [ -z "$IMAGE_TAG" ]; then
        IMAGE_TAG="latest"
    fi

    IMAGE_TAG=$(echo "$IMAGE_TAG" | tr -cs 'a-z0-9.-' '-' | sed 's/^-*//;s/-*$//')

    REGISTRY="${GCP_REGION}-docker.pkg.dev"
    FULL_IMAGE_NAME="${REGISTRY}/${GCP_PROJECT}/${GCP_REPO}/${IMAGE_NAME}:${IMAGE_TAG}"

    echo ""
    echo "Authenticating with Google Artifact Registry..."
    gcloud auth configure-docker "${REGISTRY}"
    if [ $? -ne 0 ]; then
        echo "ERROR: Artifact Registry authentication failed"
        exit 1
    fi

elif [ "$PLATFORM_CHOICE" = "2" ]; then
    echo ""
    echo "--- Docker Hub ---"
    read -p "Enter Docker Hub Username: " DOCKER_USERNAME
    read -s -p "Enter Docker Hub Password: " DOCKER_PASSWORD
    echo ""
    read -p "Enter IMAGE_TAG (press Enter for latest): " IMAGE_TAG

    if [ -z "$IMAGE_TAG" ]; then
        IMAGE_TAG="latest"
    fi

    IMAGE_TAG=$(echo "$IMAGE_TAG" | tr -cs 'a-z0-9.-' '-' | sed 's/^-*//;s/-*$//')

    FULL_IMAGE_NAME="${DOCKER_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}"

    echo ""
    echo "Logging in to Docker Hub..."
    echo "$DOCKER_PASSWORD" | docker login --username "$DOCKER_USERNAME" --password-stdin
    if [ $? -ne 0 ]; then
        echo "ERROR: Docker Hub login failed"
        exit 1
    fi

else
    echo "ERROR: Invalid choice. Exiting."
    exit 1
fi

echo ""
echo "Building Docker image..."
echo "  Image: ${FULL_IMAGE_NAME}"
docker build -f Dockerfile -t "${FULL_IMAGE_NAME}" .
if [ $? -ne 0 ]; then
    echo "ERROR: Docker build failed"
    exit 1
fi

echo ""
echo "Pushing Docker image..."
docker push "${FULL_IMAGE_NAME}"
if [ $? -ne 0 ]; then
    echo "ERROR: Docker push failed"
    exit 1
fi

echo ""
echo "=== Build and push complete ==="
echo "Image: ${FULL_IMAGE_NAME}"
