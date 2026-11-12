# ResortsLite — Deployment Guide

## Overview

ResortsLite is a Spring Boot 2.7.x resort booking application built on Java 8, deployed to **Google Kubernetes Engine (GKE)**. This guide covers building the container image, pushing it to Google Artifact Registry, and deploying it to a GKE cluster.

---

## Prerequisites

### System Requirements

| Component | Minimum Version |
|---|---|
| Docker | 20.10+ |
| Java (build) | JDK 8 |
| Maven | 3.6+ |
| gcloud CLI | 400.0.0+ |
| kubectl | 1.25+ |

### GCP Account Requirements

- A Google Cloud Platform project with billing enabled
- Permissions: `roles/container.admin`, `roles/artifactregistry.admin`, `roles/secretmanager.secretAccessor`
- Google Cloud SDK installed and authenticated

### External Services (provided separately)

The application requires the following external services, each reached through environment variables:

| Service | Environment Variable | Description |
|---|---|---|
| Database | `DB_HOST`, `DB_USER`, `DB_PASS` | H2 or external database credentials |
| Redis | `REDIS_HOST`, `REDIS_PORT` | Memorystore for Redis (sessions + cache) |
| Payment API | `PAYMENT_API_URL` | Payment service endpoint |
| Inventory API | `INVENTORY_API_URL` | Inventory service endpoint |
| Notification API | `NOTIFICATION_API_URL` | Notification service endpoint |

---

## Local Setup with Docker Compose

### 1. Set Environment Variables

```bash
export DB_USER=sa
export DB_PASS=
export DB_HOST=localhost
export REDIS_HOST=localhost
export REDIS_PORT=6379
```

### 2. Build and Run Locally

```bash
docker-compose up --build
```

The application starts on port 8080. Access it at:

- **Application**: http://localhost:8080
- **H2 Console**: http://localhost:8080/h2-console
- **Health Check**: http://localhost:8080/actuator/health

### 3. Docker Compose Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `APP_PORT` | No | 8080 | Application port |
| `DB_USER` | Yes | — | Database username |
| `DB_PASS` | Yes | — | Database password |
| `DB_HOST` | Yes | — | Database host |
| `REDIS_HOST` | Yes | — | Redis host |
| `REDIS_PORT` | No | 6379 | Redis port |
| `PAYMENT_API_URL` | No | — | Payment service URL |
| `INVENTORY_API_URL` | No | — | Inventory service URL |
| `NOTIFICATION_API_URL` | No | — | Notification service URL |
| `REPORT_BASE_PATH` | No | /app/reports | Report file directory |
| `BACKUP_PATH` | No | /app/backups | Backup file directory |

---

## Building and Pushing the Container Image

### Prerequisites

- Docker installed and running
- gcloud CLI installed and authenticated (`gcloud auth login`)
- Java 8 JDK and Maven installed

### Build and Push Script

Two scripts are provided: `scripts/build-push.sh` (Linux/macOS) and `scripts/build-push.bat` (Windows).

#### On Linux/macOS:

```bash
chmod +x scripts/build-push.sh
./scripts/build-push.sh
```

The script will:
1. Ask you to select a target platform (Google Artifact Registry or Docker Hub)
2. Prompt for registry details (region, project ID, repository name)
3. Prompt for an image tag (press Enter for `latest`)
4. Authenticate with the registry
5. Build the Docker image using the multi-stage Dockerfile
6. Push the image to the registry

#### On Windows:

```cmd
scripts\build-push.bat
```

### Manual Build

```bash
# For Google Artifact Registry
gcloud auth configure-docker us-central1-docker.pkg.dev
docker build -f Dockerfile -t us-central1-docker.pkg.dev/PROJECT_ID/REPO/resortslite:latest .
docker push us-central1-docker.pkg.dev/PROJECT_ID/REPO/resortslite:latest
```

---

## Deploying to GCP GKE

### Prerequisites

- GKE cluster running (Standard or Autopilot)
- `gcloud` and `kubectl` installed and configured
- Artifact Registry repository created
- Memorystore for Redis instance provisioned (for sessions and cache)
- Database service available (H2 in-memory or external)

### Cluster Setup

```bash
# Set your GCP project
gcloud config set project PROJECT_ID

# Get credentials for your GKE cluster
gcloud container clusters get-credentials CLUSTER_NAME --zone ZONE --project PROJECT_ID

# Verify connectivity
kubectl cluster-info
```

### Deployment Script

Two scripts are provided: `scripts/deploy-image.sh` (Linux/macOS) and `scripts/deploy-image.bat` (Windows).

#### On Linux/macOS:

```bash
chmod +x scripts/deploy-image.sh
./scripts/deploy-image.sh
```

The script will:
1. Ask for GCP project ID, zone, and cluster name
2. Configure kubectl for the target cluster
3. Ask for the full image URI (with registry and tag)
4. Ask for non-credential environment variables (payment/inventory/notification URLs)
5. Ask for credential values (DB credentials, Redis credentials) — entered securely without echo
6. Create a Kubernetes Secret with the credentials
7. Apply namespace, deployment, service, and ingress manifests
8. Wait for the deployment rollout to complete
9. Display pod/service/ingress status and the application URL

#### On Windows:

```cmd
scripts\deploy-image.bat
```

### Manual Deployment

```bash
# 1. Create namespace
kubectl apply -f kubernetes/namespace.yaml

# 2. Create Secret with credentials
kubectl create secret generic resortslite-secrets -n resortslite \
    --from-literal=DB_HOST="your-db-host" \
    --from-literal=DB_USER="your-db-user" \
    --from-literal=DB_PASS="your-db-password" \
    --from-literal=REDIS_HOST="your-redis-host" \
    --from-literal=REDIS_PORT="6379" \
    --dry-run=client -o yaml | kubectl apply -f -

# 3. Update deployment.yaml with your image URI and env vars
#    Replace {{IMAGE_URI}}, {{PAYMENT_API_URL}}, etc.

# 4. Apply manifests
kubectl apply -f kubernetes/deployment.yaml
kubectl apply -f kubernetes/service.yaml
kubectl apply -f kubernetes/ingress.yaml

# 5. Wait for rollout
kubectl rollout status deployment/resortslite -n resortslite
```

### Kubernetes Manifests

| Manifest | Description |
|---|---|
| `kubernetes/namespace.yaml` | Namespace `resortslite` |
| `kubernetes/deployment.yaml` | Deployment with 2 replicas, resource limits, Redis sessions, and health probes |
| `kubernetes/service.yaml` | ClusterIP service routing port 80 to container port 8080 |
| `kubernetes/ingress.yaml` | GCE ingress for `resortslite.example.com` |

### Health Checks

The application exposes a health check endpoint at `/actuator/health`, configured as both the liveness and readiness probe in the GKE deployment:

- **Liveness probe**: HTTP GET to `/actuator/health` on port 8080, with 60s initial delay, 15s interval
- **Readiness probe**: HTTP GET to `/actuator/health` on port 8080, with 30s initial delay, 10s interval

---

## Configuration Management

### Environment Variables

All configuration is externalized through environment variables, following the twelve-factor app methodology. No credentials or infrastructure-specific values are stored in the container image.

**Application Configuration:**

| Variable | Source | Description |
|---|---|---|
| `APP_PORT` | ConfigMap / docker-compose | Application server port |
| `DB_USER` | Secret | Database username |
| `DB_PASS` | Secret | Database password |
| `DB_HOST` | Secret | Database host |
| `REDIS_HOST` | Secret | Redis host (Memorystore) |
| `REDIS_PORT` | Secret | Redis port |
| `PAYMENT_API_URL` | ConfigMap | Payment service endpoint |
| `INVENTORY_API_URL` | ConfigMap | Inventory service endpoint |
| `NOTIFICATION_API_URL` | ConfigMap | Notification service endpoint |
| `REPORT_BASE_PATH` | ConfigMap | Report file directory |
| `BACKUP_PATH` | ConfigMap | Backup file directory |
| `SPRING_PROFILES_ACTIVE` | ConfigMap | Spring profile (prod) |

### Kubernetes Secrets

Credentials are stored in a Kubernetes Secret named `resortslite-secrets` in the `resortslite` namespace. The deploy script creates this Secret automatically.

### Kubernetes ConfigMaps

Non-sensitive configuration (service URLs, paths) can be stored in a ConfigMap. The deployment script injects these as environment variables.

---

## Security Considerations

### Credentials

- **Never** store credentials in source code or container images
- All credentials are injected via Kubernetes Secrets at runtime
- The deploy script creates Secrets from user-provided values (entered securely)
- DB credentials, Redis credentials are never written to disk or logs

### Network Security

- Internal service calls use Kubernetes DNS names (not IP addresses)
- The application listens on port 8080 internally
- The GKE Ingress terminates external traffic
- All external service endpoints are configurable via environment variables

### Container Security

- The container runs as a non-root user (UID 1000)
- Resource limits are set (CPU: 500m, Memory: 1Gi)
- The container image is built from `eclipse-temurin:8-jdk` (minimal base)
- No package managers or unnecessary tools are installed in the runtime image

### Dependency Security

- Log4j 2.14.1 (CVE-2021-44228) and commons-collections 3.2.1 (CVE-2015-6420) are present in the original pom.xml as intentional legacy patterns. These should be upgraded before production use.

---

## Java Notes

### JVM Settings

The container runs with the following JVM settings optimized for containerized environments:

```
JAVA_OPTS="-Xmx512m -Xms256m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"
```

- `-Xmx512m`: Maximum heap size of 512MB
- `-Xms256m`: Initial heap size of 256MB
- `-XX:+UseContainerSupport`: Enables container-aware memory management
- `-XX:MaxRAMPercentage=75.0`: Uses 75% of the container's memory limit for the heap

These settings align with the GKE deployment's resource limits (512Mi request, 1Gi limit).

### Spring Profiles

The application uses the `prod` profile by default (`SPRING_PROFILES_ACTIVE=prod`). The H2 in-memory database is used for development; in production, an external database should be configured via `DB_HOST`, `DB_USER`, and `DB_PASS` environment variables.

### Health Endpoints

Spring Boot Actuator provides the health check endpoint at `/actuator/health`. This endpoint is used by GKE for liveness and readiness probes. The endpoint returns:

- `200 OK` with `{"status":"UP"}` when the application is healthy
- `503 Service Unavailable` with `{"status":"DOWN"}` when the application is unhealthy

### Session Management

HTTP sessions are externalized to Redis via Spring Session (`@EnableRedisHttpSession`). This ensures session persistence across pod restarts and horizontal scaling. The Redis connection is configured via `REDIS_HOST` and `REDIS_PORT` environment variables.

### Caching

Local in-memory caching is replaced with Redis-backed caching via Spring Cache (`@EnableCaching`). The Redis connection is shared with the session store. Cache TTL is configured to 20 minutes (`spring.cache.redis.time-to-live=1200000`).

### Logging

The application uses Log4j 2 (log4j-core 2.14.1). Logging configuration is handled by Spring Boot's default logging setup. In production, consider upgrading log4j to a patched version (2.17.1+) to address CVE-2021-44228.

---

## Troubleshooting

### Pod Fails to Start

```bash
# Check pod status
kubectl get pods -n resortslite

# Check pod logs
kubectl logs <pod-name> -n resortslite

# Describe pod for events
kubectl describe pod <pod-name> -n resortslite
```

Common issues:
- **ImagePullBackOff**: Verify the image URI and Artifact Registry authentication
- **CrashLoopBackOff**: Check application logs for startup errors (e.g., missing Redis)
- **Pending**: Check resource quotas and node availability

### Service Issues

```bash
# Check service
kubectl get svc -n resortslite

# Test connectivity from a debug pod
kubectl run debug --image=gcr.io/google-containers/busybox --rm -it -- sh
```

### Ingress Problems

```bash
# Check ingress
kubectl get ingress -n resortslite

# Check ingress controller logs
kubectl logs -n kube-system -l app=glbc
```

Common issues:
- **404**: Verify the host header matches `resortslite.example.com`
- **502**: Check that the service is running and the backend is healthy

### Redis Connection Issues

```bash
# Check Redis connectivity from a pod
kubectl exec -it <pod-name> -n resortslite -- redis-cli -h $REDIS_HOST ping
```

Common issues:
- **Connection refused**: Verify `REDIS_HOST` and `REDIS_PORT` in the Secret
- **Permission denied**: Check Workload Identity configuration and Secret Manager permissions

---

## Scaling and Management

### Horizontal Pod Autoscaler

To enable auto-scaling based on CPU utilization:

```bash
kubectl autoscale deployment resortslite --cpu-percent=65 --min=2 --max=10 -n resortslite
```

### Rolling Updates

```bash
# Update the image
kubectl set image deployment/resortslite resortslite=NEW_IMAGE_URI -n resortslite

# Monitor rollout
kubectl rollout status deployment/resortslite -n resortslite

# Rollback if needed
kubectl rollout undo deployment/resortslite -n resortslite
```

### Manual Rollback

If the deploy script is used, rollback instructions are printed at the end. For manual rollback:

```bash
kubectl rollout undo deployment/resortslite -n resortslite
```

### Scaling Replicas

```bash
# Scale up
kubectl scale deployment resortslite --replicas=5 -n resortslite

# Scale down
kubectl scale deployment resortslite --replicas=2 -n resortslite
```
