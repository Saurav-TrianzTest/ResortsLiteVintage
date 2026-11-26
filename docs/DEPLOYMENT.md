# ResortsLite - Deployment Guide (AWS EKS)

## Application summary
- Spring Boot 2.7.18, Java 8, Maven, executable JAR
- Port: 8080 (`SERVER_PORT`), health: `/actuator/health` (+ `/liveness`, `/readiness` probes)
- External dependency: Redis / ElastiCache (Spring Session + booking cache)
- Runtime image: `eclipse-temurin:8-jdk` (explicit base image); builder: `maven:3.9.4-eclipse-temurin-8`

## Prerequisites
Docker, AWS CLI v2 (configured), kubectl, eksctl (optional), an EKS cluster with the AWS Load Balancer Controller installed, and IAM permissions for ECR (push) and EKS (`eks:DescribeCluster`).

## Local development
```
export REDIS_HOST=host.docker.internal
docker compose up --build
curl http://localhost:8080/actuator/health
```
Redis must be provided separately (not part of compose).

## Build and push
Run from the repository root:
- Linux/macOS: `./scripts/build-push.sh`
- Windows: `scripts\build-push.bat`

Choose AWS ECR or Docker Hub; the ECR repository is created automatically. Note the final image URI.

## EKS setup
```
aws eks update-kubeconfig --region <region> --name <cluster>
kubectl cluster-info
```

## Deploy
`./scripts/deploy-image.sh` (or `.bat`) prompts for region, cluster, image URI and Redis settings, substitutes `{{PLACEHOLDER}}` values in a temporary copy of `kubernetes/`, creates the `resortslite-secrets` secret (REDIS_PASSWORD) and applies: namespace -> deployment -> service -> ingress, then waits for rollout.

Manifests:
- `namespace.yaml` - namespace `resortslite`
- `deployment.yaml` - 2 replicas, 250m/512Mi requests, 500m/1Gi limits, startup/liveness/readiness probes
- `service.yaml` - ClusterIP 80 -> 8080
- `ingress.yaml` - ALB internet-facing; change host `resortslite.example.com`

## Configuration
| Variable | Default | Purpose |
|---|---|---|
| SERVER_PORT | 8080 | HTTP port |
| REDIS_HOST / REDIS_PORT | localhost / 6379 | ElastiCache endpoint |
| REDIS_PASSWORD | empty | stored in Kubernetes Secret |
| REDIS_SSL_ENABLED | false | TLS to Redis |
| SESSION_REDIS_NAMESPACE | resortslite:session | session key namespace |
| BOOKING_CACHE_KEY_PREFIX / BOOKING_CACHE_TTL_SECONDS | resortslite:booking: / 3600 | booking cache |
| REPORT_BASE_PATH / REPORT_BACKUP_PATH | /app/reports/, /app/backups/nightly/ | report files (emptyDir in EKS - use a PVC/EFS if persistence is needed) |
| JAVA_OPTS | container-aware JVM flags | JVM tuning |

## Scaling and management
```
kubectl scale deployment/resortslite -n resortslite --replicas=4
kubectl autoscale deployment resortslite -n resortslite --cpu-percent=70 --min=2 --max=6
kubectl set image deployment/resortslite resortslite=<new-image> -n resortslite
kubectl rollout undo deployment/resortslite -n resortslite
```

## Troubleshooting
- Pods CrashLoopBackOff: `kubectl logs <pod> -n resortslite`; check Redis connectivity/security groups (readiness depends on Redis health).
- ImagePullBackOff: verify the image URI and node role ECR read permissions.
- Ingress has no address: confirm AWS Load Balancer Controller is running (`kubectl get pods -n kube-system`) and subnets are tagged.
- Probes failing: `kubectl describe pod <pod> -n resortslite`; JVM startup may need longer `startupProbe`.

## Security notes
- Container runs as non-root (uid 1001). Secrets are kept in Kubernetes Secrets (consider AWS Secrets Manager / External Secrets).
- The app has H2 console enabled and known vulnerable dependencies (log4j-core 2.14.1, commons-collections 3.2.1); remediate before production.
- Hardcoded internal service endpoints (`app.*.endpoint`) should be externalised.
- Only `/actuator/health` is exposed. Serve over HTTPS by adding an ACM certificate annotation to the ingress.
