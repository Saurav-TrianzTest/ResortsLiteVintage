# ResortsLite Deployment Guide

## Prerequisites and System Requirements

### Target Platform: Azure Kubernetes Service (AKS)

The following tools and accounts are required:

- **Azure CLI** (`az`) — for authenticating to Azure and configuring kubectl
- **kubectl** — for deploying and managing Kubernetes resources
- **Docker** — for building and pushing container images
- **An Azure subscription** with permissions to create AKS clusters and Azure Container Registry
- **An Azure Container Registry (ACR)** instance for storing container images
- **An Azure Cache for Redis** instance for session and cache storage
- **An AKS cluster** with the Azure Application Gateway Ingress Controller (AGIC) add-on enabled

### Java Notes

- **Java version**: Java 8 (JDK 8)
- **Build tool**: Maven 3.8+
- **Framework**: Spring Boot 2.7.18
- **Packaging**: Runnable JAR (spring-boot-maven-plugin)

#### JVM Settings for Container

The Dockerfile sets the following JVM options for containerized deployment:

```
JAVA_OPTS="-Xmx512m -Xms256m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"
```

- `-Xmx512m`: Maximum heap size of 512 MB
- `-Xms256m`: Initial heap size of 256 MB
- `-XX:+UseContainerSupport`: Enables container-aware memory management (default in Java 8u191+)
- `-XX:MaxRAMPercentage=75.0`: Uses up to 75% of the container's memory limit for the heap

The Kubernetes deployment sets resource limits of 512Mi memory and 500m CPU, so the JVM heap is tuned to stay within these limits.

#### Spring Profiles

The application uses the `prod` Spring profile by default (`SPRING_PROFILES_ACTIVE=prod`).

#### Health Endpoints

The application exposes health check endpoints via Spring Boot Actuator:

- **Liveness probe**: `GET /actuator/health` — used by Kubernetes to determine if the pod should be restarted
- **Readiness probe**: `GET /actuator/health` — used by Kubernetes to determine if the pod is ready to receive traffic

These endpoints are configured in `application.properties`:

```properties
management.endpoints.web.exposure.include=health
management.endpoint.health.show-details=always
```

## Local Setup with Docker Compose

To run the application locally with Docker Compose:

1. Ensure Docker is running
2. Set the required environment variables:

```bash
export REDIS_HOST=localhost
export REDIS_PASSWORD=
export PAYMENT_API=http://localhost:9090/payments/charge
```

3. Build and run:

```bash
docker-compose up --build
```

4. Access the application at `http://localhost:8080`

The Docker Compose file mounts a local `config` directory for configuration files and a persistent data volume for reports and backups.

## Building and Pushing Container Images

### Prerequisites

- Docker installed and running
- Azure CLI installed (for Azure ACR) or Docker Hub credentials

### Build and Push

Use the build script to build and push the container image:

**Linux/macOS:**

```bash
chmod +x scripts/build-push.sh
./scripts/build-push.sh
```

**Windows:**

```cmd
scripts\build-push.bat
```

The script will:

1. Ask you to choose a target registry (Azure ACR or Docker Hub)
2. Prompt for registry details (ACR name or Docker Hub credentials)
3. Prompt for an image tag (defaults to `latest`)
4. Build the Docker image using the multi-stage Dockerfile
5. Log in to the chosen registry
6. Push the image

### Docker Build Details

The Dockerfile uses a multi-stage build:

- **Build stage**: `maven:3.8.6-openjdk-8-slim` — compiles the Java 8 source and packages the runnable JAR
- **Runtime stage**: `eclipse-temurin:8-jdk` — runs the JAR with a non-root user

The build context is the project root (`.`), and the build context always includes only the source code and `pom.xml`.

## Configuration Management and Environment Variables

The application reads configuration from environment variables, which are injected through Kubernetes ConfigMaps and Secrets on AKS.

### Environment Variables

| Variable | Description | Default | Source |
|---|---|---|---|
| `APP_PORT` | Server port | `8080` | ConfigMap |
| `REDIS_HOST` | Redis host for sessions and cache | `localhost` | ConfigMap |
| `REDIS_PORT` | Redis port | `6379` | ConfigMap |
| `REDIS_PASSWORD` | Redis password | *(empty)* | Secret (Key Vault CSI) |
| `REDIS_SSL` | Enable Redis TLS | `false` | ConfigMap |
| `REPORT_BASE_PATH` | Report storage directory | `/app/data/reports` | ConfigMap |
| `BACKUP_PATH` | Backup storage directory | `/app/data/backups` | ConfigMap |
| `PAYMENT_API` | Payment service endpoint | `http://localhost:9090/payments/charge` | ConfigMap |
| `SPRING_PROFILES_ACTIVE` | Spring profile | `prod` | ConfigMap |
| `JAVA_OPTS` | JVM options | *(see Dockerfile)* | ConfigMap |

### Kubernetes Secrets

Sensitive values (credentials) are stored in a Kubernetes Secret named `resortslite-secrets` and injected as environment variables via `secretKeyRef`. On AKS, these secrets are sourced from Azure Key Vault using the Secrets Store CSI Driver.

The deploy script creates the Secret before deploying the application:

```bash
kubectl create secret generic resortslite-secrets -n resortslite \
    --from-literal=REDIS_PASSWORD="$REDIS_PASSWORD" \
    --dry-run=client -o yaml | kubectl apply -f -
```

### ConfigMaps

Non-sensitive configuration values are stored in a Kubernetes ConfigMap and referenced in the deployment via environment variables.

## Security Considerations and Best Practices

1. **Non-root user**: The Docker image runs as a non-root user (`appuser`) for security.
2. **Secrets management**: All credentials (Redis password) are stored in Kubernetes Secrets, not in the container image or source code.
3. **TLS**: Redis connections should use TLS (`REDIS_SSL=true`) in production. Azure Cache for Redis uses port 6380 with TLS.
4. **Resource limits**: The deployment sets CPU and memory requests and limits to prevent resource exhaustion.
5. **Health checks**: Liveness and readiness probes ensure unhealthy pods are restarted and removed from service.
6. **Image scanning**: Regularly scan container images for vulnerabilities.
7. **Network policies**: Use AKS network policies to restrict pod-to-pod communication.
8. **Azure Key Vault**: Store all secrets in Azure Key Vault and use the Secrets Store CSI Driver to mount them in pods.

## Deployment to Azure AKS

### AKS Cluster Setup

1. Create an AKS cluster with AGIC (Azure Application Gateway Ingress Controller):

```bash
az aks create \
    --resource-group myResourceGroup \
    --name myAKSCluster \
    --node-vm-size Standard_DS2_v2 \
    --node-count 2 \
    --enable-aad \
    --enable-addons monitoring,azure-keyvault-secrets-provider \
    --enable-oidc-issuer \
    --enable-workload-identity \
    --generate-ssh-keys
```

2. Configure kubectl:

```bash
az aks get-credentials --resource-group myResourceGroup --name myAKSCluster
```

3. Verify cluster connectivity:

```bash
kubectl cluster-info
```

### Deployment Walkthrough

The deployment consists of four Kubernetes manifests:

1. **`kubernetes/namespace.yaml`** — Creates the `resortslite` namespace
2. **`kubernetes/deployment.yaml`** — Defines the Deployment with 2 replicas, resource limits, probes, and environment variables
3. **`kubernetes/service.yaml`** — Exposes the application internally via a ClusterIP service on port 80
4. **`kubernetes/ingress.yaml`** — Routes external traffic through Azure Application Gateway to the service

### Deploying the Application

Use the deploy script:

**Linux/macOS:**

```bash
chmod +x scripts/deploy-image.sh
./scripts/deploy-image.sh
```

**Windows:**

```cmd
scripts\deploy-image.bat
```

The script will:

1. Ask for the Azure resource group and AKS cluster name
2. Configure kubectl with `az aks get-credentials`
3. Verify cluster connectivity
4. Ask for the full image URI (e.g., `myacr.azurecr.io/resortslite:latest`)
5. Ask for non-sensitive environment variables (REDIS_HOST, PAYMENT_API)
6. Ask for credentials (REDIS_PASSWORD) without echoing
7. Apply the namespace
8. Create the Kubernetes Secret with credentials
9. Replace placeholders in deployment.yaml and apply it
10. Apply the service and ingress
11. Wait for the deployment to be ready
12. Show pod, service, and ingress status
13. Display the application URL

### Manual Deployment

Alternatively, you can deploy manually:

```bash
# Apply namespace
kubectl apply -f kubernetes/namespace.yaml

# Create secret
kubectl create secret generic resortslite-secrets -n resortslite \
    --from-literal=REDIS_PASSWORD="your-redis-password" \
    --dry-run=client -o yaml | kubectl apply -f -

# Substitute placeholders and apply deployment
sed 's|{{IMAGE_URI}}|myacr.azurecr.io/resortslite:latest|g' \
    kubernetes/deployment.yaml | kubectl apply -f -

# Apply service and ingress
kubectl apply -f kubernetes/service.yaml
kubectl apply -f kubernetes/ingress.yaml

# Wait for deployment
kubectl rollout status deployment/resortslite -n resortslite
```

### Troubleshooting

#### Pod Failures

- **ImagePullBackOff**: Verify the image URI is correct and you are logged in to the registry
- **CrashLoopBackOff**: Check pod logs with `kubectl logs <pod-name> -n resortslite`
- **ErrImagePull**: Ensure the ACR credentials are configured or the image exists

#### Service Issues

- **502 Bad Gateway**: Verify the service selector matches the deployment labels
- **Connection refused**: Check that the container port matches the service targetPort
- **DNS resolution**: Use `kubectl exec` to test connectivity from within a pod

#### Ingress Problems

- **404 Not Found**: Verify the ingress host matches the configured domain
- **502 Bad Gateway**: Check that the Application Gateway ingress controller is running
- **SSL redirect**: The ingress has `ssl-redirect: "443"` annotation; ensure TLS is configured

#### Session/Cache Issues

- **Redis connection failures**: Verify `REDIS_HOST` and `REDIS_PASSWORD` are set correctly in the Secret
- **Session loss**: Ensure Redis is running and accessible from the AKS cluster
- **Cache misses**: Verify `BOOKING_CACHE_TTL_SECONDS` is set if using custom cache TTL

### Scaling and Management

#### Horizontal Pod Autoscaler (HPA)

To enable auto-scaling based on CPU usage:

```bash
kubectl autoscale deployment resortslite \
    --cpu-percent=70 \
    --min=2 \
    --max=10 \
    -n resortslite
```

#### Rolling Updates

To update the image:

```bash
# Update the image
kubectl set image deployment/resortslite resortslite=myacr.azurecr.io/resortslite:new-tag -n resortslite

# Monitor the rollout
kubectl rollout status deployment/resortslite -n resortslite
```

#### Rollback

To rollback to a previous revision:

```bash
# View rollout history
kubectl rollout history deployment/resortslite -n resortslite

# Rollback to the previous revision
kubectl rollout undo deployment/resortslite -n resortslite

# Rollback to a specific revision
kubectl rollout undo deployment/resortslite --to-revision=2 -n resortslite
```

#### Viewing Logs

```bash
# View logs from a specific pod
kubectl logs <pod-name> -n resortslite

# Follow logs
kubectl logs -f <pod-name> -n resortslite

# View logs from all pods in the deployment
kubectl logs -l app=resortslite -n resortslite
```

