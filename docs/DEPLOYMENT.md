# ResortsLite (RLEKS) — Deployment Guide

## Overview

ResortsLite is a Spring Boot 2.7.x resort booking application built with Java 8 and Maven. This guide covers containerizing the application and deploying it to AWS ECS Fargate.

## Prerequisites

### System Requirements

- **Java**: JDK 8 (for local development)
- **Maven**: 3.6+
- **Docker**: 20.10+
- **AWS CLI**: 2.0+
- **AWS Account** with permissions for ECS, ECR, IAM, Secrets Manager, CloudWatch, and EC2

### AWS Prerequisites

- A VPC with at least two subnets in different Availability Zones
- A security group that allows inbound traffic on port 8080 (the application port)
- IAM permissions for ECS, ECR, Secrets Manager, CloudWatch Logs, and EC2 networking
- The `ecsTaskExecutionRole` role (for pulling images and writing logs)
- The `ecsTaskRole` role (for task-level permissions)

## Local Setup with Docker Compose

1. Create a `.env` file with the required credentials:

```bash
DB_URL=jdbc:h2:mem:resortdb;DB_CLOSE_DELAY=-1
DB_USERNAME=sa
DB_PASSWORD=
PAYMENT_API_URL=http://payment-svc.internal:9090/charge
INVENTORY_API_URL=http://inventory-svc.internal:8081/rooms
NOTIFICATION_API_URL=http://notify.internal:7070/send
```

2. Build and run locally:

```bash
docker-compose up --build
```

3. Access the application:
- Application: http://localhost:8080
- Health check: http://localhost:8080/actuator/health
- H2 Console: http://localhost:8080/h2-console

## Building and Pushing the Container Image

### Using the Shell Script (Linux/macOS)

```bash
chmod +x scripts/build-push.sh
./scripts/build-push.sh
```

The script will prompt for:
- AWS region (e.g., `us-east-1`)
- ECR repository name (e.g., `rleks`)
- Image tag (leave empty for `latest`)

It will:
1. Retrieve your AWS account ID
2. Log in to Amazon ECR
3. Create the ECR repository if it doesn't exist
4. Build the Docker image using the multi-stage Dockerfile
5. Push the image to ECR

### Using the Batch Script (Windows)

```cmd
scripts\build-push.bat
```

The script follows the same steps as the shell script.

### Manual Build

```bash
docker build -f Dockerfile -t rleks:latest .
```

## AWS ECS Fargate Deployment

### Using the Deployment Script

```bash
chmod +x scripts/deploy-image.sh
./scripts/deploy-image.sh
```

The script will prompt for:
- AWS region (e.g., `us-east-1`)
- ECS cluster name
- VPC ID
- Subnet IDs (comma-separated, at least two)
- Security group ID (must allow traffic on port 8080)
- Full image URI (e.g., `123456789.dkr.ecr.us-east-1.amazonaws.com/rleks:latest`)
- Whether a load balancer is needed (y/n)
- Database credentials (DB_USERNAME, DB_PASSWORD)

The script will:
1. Create the ECS cluster if it doesn't exist
2. Optionally create an Application Load Balancer with a target group (health check on `/actuator/health`)
3. Store database credentials in AWS Secrets Manager
4. Create the CloudWatch log group `/ecs/rleks` if it doesn't exist
5. Register the task definition with resolved placeholders
6. Create or update the ECS service
7. Wait for the service to become stable
8. Display the deployment summary and troubleshooting hints

### Fargate Setup

The ECS task definition (`ecs/task-definition.json`) is configured for Fargate:

- **Launch type**: FARGATE
- **Network mode**: awsvpc
- **CPU**: 512 (0.5 vCPU)
- **Memory**: 1024 MB
- **Execution role**: `arn:aws:iam::{{ACCOUNT_ID}}:role/ecsTaskExecutionRole`
- **Task role**: `arn:aws:iam::{{ACCOUNT_ID}}:role/ecsTaskRole`

The task includes an EFS volume mounted at `/app/data` for persistent storage of reports and backups across task restarts.

### CloudWatch Log Group

The log group `/ecs/rleks` is created automatically by the deployment script. Application logs are streamed to CloudWatch with the prefix `ecs`.

### Execution Role Permissions

The `ecsTaskExecutionRole` must have permissions to:
- Pull images from ECR (`AmazonEC2ContainerRegistryReadOnly`)
- Write logs to CloudWatch (`CloudWatchLogsFullAccess` or scoped policy)
- Read secrets from Secrets Manager (`secretsmanager:GetSecretValue` on `rleks/*` secrets)

Example IAM policy for Secrets Manager access:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "secretsmanager:GetSecretValue",
      "Resource": "arn:aws:secretsmanager:*:*:secret:rleks/*"
    }
  ]
}
```

### Task Definition Explained

The task definition (`ecs/task-definition.json`) contains:

- **family**: `rleks-task` — the task definition family name
- **requiresCompatibilities**: `FARGATE` — runs on AWS Fargate
- **networkMode**: `awsvpc` — required for Fargate
- **cpu/memory**: `512`/`1024` — Fargate compute allocation
- **containerDefinitions**: Single container `rleks` running the application JAR
  - **image**: Resolved from `{{IMAGE_URI}}` placeholder
  - **portMappings**: Container port 8080 (TCP)
  - **environment**: Non-sensitive configuration (port, paths, profiles, service URLs)
  - **secrets**: Database credentials (DB_USERNAME, DB_PASSWORD) from Secrets Manager
  - **logConfiguration**: awslogs driver writing to `/ecs/rleks`
- **volumes**: EFS volume `efs-data` mounted at `/app/data` for persistent storage

### Service Configuration

The service definition (`ecs/service-definition.json`) contains:

- **serviceName**: `rleks-service`
- **desiredCount**: 2 (for high availability)
- **launchType**: FARGATE
- **networkConfiguration**: awsvpc with two subnets and a security group
- **deploymentConfiguration**: `maximumPercent: 200`, `minimumHealthyPercent: 50`
- **loadBalancers**: Optional ALB target group on port 8080
- **healthCheckGracePeriodSeconds**: 300 (for slow startup)

## Configuration Management

The application reads configuration from environment variables. Sensitive values are injected via AWS Secrets Manager (in the ECS task definition `secrets` block) and non-sensitive values via the `environment` block.

| Variable | Source | Description |
|---|---|---|
| `APP_PORT` | Environment | Application port (default: 8080) |
| `DB_URL` | Environment | Database JDBC URL |
| `DB_USERNAME` | Secrets Manager | Database username |
| `DB_PASSWORD` | Secrets Manager | Database password |
| `PAYMENT_API_URL` | Environment | Payment service endpoint |
| `INVENTORY_API_URL` | Environment | Inventory service endpoint |
| `NOTIFICATION_API_URL` | Environment | Notification service endpoint |
| `DATA_PATH` | Environment | Base data directory (default: /app/data) |
| `BACKUP_PATH` | Environment | Backup directory (default: /app/data/backups) |
| `SPRING_PROFILES_ACTIVE` | Environment | Active Spring profile (default: prod) |

### Environment Variables for Docker Compose

When running locally with Docker Compose, provide the following environment variables:

```bash
export DB_URL=jdbc:h2:mem:resortdb;DB_CLOSE_DELAY=-1
export DB_USERNAME=sa
export DB_PASSWORD=
export PAYMENT_API_URL=http://payment-svc.internal:9090/charge
export INVENTORY_API_URL=http://inventory-svc.internal:8081/rooms
export NOTIFICATION_API_URL=http://notify.internal:7070/send
```

## Security Considerations

- **Credentials**: Database credentials are stored in AWS Secrets Manager, never in source code or container images.
- **Health checks**: The application exposes `/actuator/health` for load balancer health checks.
- **Non-root user**: The container runs as a non-root user (`appuser`).
- **EFS encryption**: EFS volumes use transit encryption (`transitEncryption: ENABLED`).
- **Security groups**: Restrict inbound traffic to only necessary ports (8080 for the application).
- **Log4j**: The project includes log4j-core 2.14.1 which has the Log4Shell vulnerability (CVE-2021-44228). This should be upgraded to 2.17.1+ in a future update.
- **commons-collections**: The project includes commons-collections 3.2.1 which has a deserialization vulnerability (CVE-2015-6420). This should be upgraded in a future update.

## Scaling and Management

### Service Auto Scaling

To configure auto scaling for the ECS service:

```bash
aws application-autoscaling register-scalable-target \
    --service-namespace ecs \
    --resource-id "service/${CLUSTER_NAME}/${SERVICE_NAME}" \
    --scalable-dimension "ecs:service:DesiredCount" \
    --min-capacity 2 \
    --max-capacity 10
```

Then create a scaling policy based on CPU or memory utilization.

### Blue/Green Deployments

For blue/green deployments using AWS CodeDeploy:
1. Create two target groups (blue and green)
2. Configure the ALB listener rule to route to the blue target group
3. Use CodeDeploy to shift traffic from blue to green

## Java Notes

### JVM Settings

The container uses the following JVM settings via `JAVA_OPTS`:

- `-Xmx512m`: Maximum heap size of 512 MB
- `-Xms256m`: Initial heap size of 256 MB
- `-XX:+UseContainerSupport`: Enables container-aware memory management
- `-XX:MaxRAMPercentage=75.0`: Uses up to 75% of container memory for the heap

These settings are tuned for the Fargate task's 1024 MB memory allocation. Adjust `cpu` and `memory` in the task definition if the application requires more resources.

### Spring Profiles

The application uses Spring profiles for environment-specific configuration:

- **dev**: Local development (H2 in-memory database)
- **prod**: Production (external database, EFS-backed file paths)

Set `SPRING_PROFILES_ACTIVE=prod` in the ECS task definition environment for production deployments.

### Health Check Endpoint

The application exposes a health check endpoint at `/actuator/health` via Spring Boot Actuator. This endpoint is used by the ALB target group for health checks. The endpoint returns HTTP 200 when the application is healthy.

### Container Image

The Dockerfile uses a multi-stage build:

1. **Build stage**: `maven:3.8.6-openjdk-8-slim` — compiles the application and creates a runnable JAR
2. **Runtime stage**: `eclipse-temurin:8-jdk` — runs the JAR with a non-root user

The build stage copies `pom.xml` first to leverage Docker layer caching for dependencies, then copies the source code and runs `mvn clean package -DskipTests`.

## Troubleshooting

### Task Failures

- **Stopped task**: Check the stopped reason in the ECS console or via `aws ecs describe-tasks`
- **Exit code 137**: Out of memory — increase the task memory allocation
- **Cannot pull image**: Verify ECR permissions on the execution role

### Network Issues

- **Security groups**: Ensure the task security group allows outbound traffic and the ALB security group allows inbound on port 8080
- **VPC configuration**: Ensure subnets have route table entries to a NAT gateway or have public IPs assigned
- **Service endpoints**: Verify that internal service endpoints (payment, inventory, notification) are reachable from the VPC

### CPU and Memory Errors

- Monitor CloudWatch metrics for CPU and memory utilization
- If the application is throttled, increase `cpu` and `memory` in the task definition
- Adjust `JAVA_OPTS` heap settings proportionally to the container memory limit

### Health Check Failures

- Verify the application is listening on port 8080
- Check that `/actuator/health` returns HTTP 200
- Increase `healthCheckGracePeriodSeconds` if the application takes longer to start
