#!/bin/bash
set -e
set -o pipefail

echo "=== ResortsLite (RLEKS) ECS Fargate Deployment Script ==="
echo ""

# Ask for AWS region
read -p "Enter AWS region (e.g., us-east-1): " AWS_REGION

# Get account ID
echo "Retrieving AWS account ID..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account ID: ${ACCOUNT_ID}"
echo ""

# Ask for cluster and VPC details
read -p "Enter ECS cluster name: " CLUSTER_NAME
read -p "Enter VPC ID: " VPC_ID
read -p "Enter subnet IDs (comma-separated, at least two): " SUBNETS
read -p "Enter security group ID: " SECURITY_GROUP

# Parse subnets
SUBNET_1=$(echo "$SUBNETS" | cut -d',' -f1 | xargs)
SUBNET_2=$(echo "$SUBNETS" | cut -d',' -f2 | xargs)

# Ask for image URI
read -p "Enter full image URI (e.g., 123456789.dkr.ecr.us-east-1.amazonaws.com/rleks:latest): " IMAGE_URI

# Create cluster if it doesn't exist
echo ""
echo "Checking if ECS cluster '${CLUSTER_NAME}' exists..."
if aws ecs describe-clusters --clusters "$CLUSTER_NAME" --region "$AWS_REGION" 2>/dev/null | grep -q "clusterName"; then
    echo "Cluster already exists."
else
    echo "Creating ECS cluster '${CLUSTER_NAME}'..."
    aws ecs create-cluster --cluster-name "$CLUSTER_NAME" --region "$AWS_REGION"
    echo "Cluster created."
fi
echo ""

# Ask about load balancer
read -p "Do you need a load balancer for this service? (y/n): " NEED_LB

SERVICE_NAME="rleks-service"
TARGET_GROUP_ARN=""

if [ "$NEED_LB" = "y" ] || [ "$NEED_LB" = "Y" ]; then
    echo ""
    echo "Creating Application Load Balancer and target group..."
    
    # Create security group for ALB
    ALB_SG=$(aws ec2 create-security-group --group-name "rleks-alb-sg" --description "Security group for RLEKS ALB" --vpc-id "$VPC_ID" --region "$AWS_REGION" --query 'GroupId' --output text)
    echo "ALB Security Group: ${ALB_SG}"
    
    # Allow HTTP traffic on port 8080
    aws ec2 authorize-security-group-ingress --group-id "$ALB_SG" --protocol tcp --port 8080 --cidr 0.0.0.0/0 --region "$AWS_REGION"
    
    # Create target group
    TARGET_GROUP_ARN=$(aws elbv2 create-target-group \
        --name "rleks-tg" \
        --protocol HTTP \
        --port 8080 \
        --vpc-id "$VPC_ID" \
        --target-type ip \
        --health-check-path "/actuator/health" \
        --health-check-port "8080" \
        --region "$AWS_REGION" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text)
    echo "Target Group ARN: ${TARGET_GROUP_ARN}"
    
    # Create ALB
    ALB_ARN=$(aws elbv2 create-load-balancer \
        --name "rleks-alb" \
        --subnets "$SUBNET_1" "$SUBNET_2" \
        --security-groups "$ALB_SG" \
        --scheme internet-facing \
        --type application \
        --region "$AWS_REGION" \
        --query 'LoadBalancers[0].LoadBalancerArn' \
        --output text)
    echo "ALB ARN: ${ALB_ARN}"
    
    # Create listener
    aws elbv2 create-listener \
        --load-balancer-arn "$ALB_ARN" \
        --protocol HTTP \
        --port 80 \
        --default-actions "Type=forward,TargetGroupArn=${TARGET_GROUP_ARN}" \
        --region "$AWS_REGION"
    echo "Listener created on port 80."
    
    # Get ALB DNS name
    ALB_DNS=$(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" --region "$AWS_REGION" --query 'LoadBalancers[0].DNSName' --output text)
    echo "ALB DNS: ${ALB_DNS}"
    echo ""
else
    echo "No load balancer requested."
    echo ""
fi

# Handle credentials: ask for DB_USERNAME and DB_PASSWORD
echo "Enter credentials for the application:"
echo ""
read -p "Enter DB_USERNAME: " DB_USERNAME_VALUE
read -s -p "Enter DB_PASSWORD: " DB_PASSWORD_VALUE
echo ""

# Store credentials in Secrets Manager
echo "Storing credentials in AWS Secrets Manager..."

DB_USERNAME_SECRET_NAME="rleks/DB_USERNAME"
DB_PASSWORD_SECRET_NAME="rleks/DB_PASSWORD"

# DB_USERNAME secret
if aws secretsmanager describe-secret --secret-id "$DB_USERNAME_SECRET_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
    echo "Updating secret '${DB_USERNAME_SECRET_NAME}'..."
    aws secretsmanager put-secret-value --secret-id "$DB_USERNAME_SECRET_NAME" --secret-string "$DB_USERNAME_VALUE" --region "$AWS_REGION"
else
    echo "Creating secret '${DB_USERNAME_SECRET_NAME}'..."
    aws secretsmanager create-secret --name "$DB_USERNAME_SECRET_NAME" --secret-string "$DB_USERNAME_VALUE" --region "$AWS_REGION"
fi
DB_USERNAME_SECRET_ARN=$(aws secretsmanager describe-secret --secret-id "$DB_USERNAME_SECRET_NAME" --region "$AWS_REGION" --query 'ARN' --output text)
echo "DB_USERNAME secret ARN: ${DB_USERNAME_SECRET_ARN}"

# DB_PASSWORD secret
if aws secretsmanager describe-secret --secret-id "$DB_PASSWORD_SECRET_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
    echo "Updating secret '${DB_PASSWORD_SECRET_NAME}'..."
    aws secretsmanager put-secret-value --secret-id "$DB_PASSWORD_SECRET_NAME" --secret-string "$DB_PASSWORD_VALUE" --region "$AWS_REGION"
else
    echo "Creating secret '${DB_PASSWORD_SECRET_NAME}'..."
    aws secretsmanager create-secret --name "$DB_PASSWORD_SECRET_NAME" --secret-string "$DB_PASSWORD_VALUE" --region "$AWS_REGION"
fi
DB_PASSWORD_SECRET_ARN=$(aws secretsmanager describe-secret --secret-id "$DB_PASSWORD_SECRET_NAME" --region "$AWS_REGION" --query 'ARN' --output text)
echo "DB_PASSWORD secret ARN: ${DB_PASSWORD_SECRET_ARN}"
echo ""

# Create log group if it doesn't exist
echo "Checking if log group '/ecs/rleks' exists..."
LOG_GROUP_EXISTS=$(aws logs describe-log-groups --log-group-name-prefix "/ecs/rleks" --region "$AWS_REGION" --query 'logGroups[?logGroupName==`/ecs/rleks`].logGroupName' --output text)
if [ -z "$LOG_GROUP_EXISTS" ]; then
    echo "Creating log group '/ecs/rleks'..."
    aws logs create-log-group --log-group-name "/ecs/rleks" --region "$AWS_REGION"
    echo "Log group created."
else
    echo "Log group already exists."
fi
echo ""

# Replace placeholders in task definition
echo "Generating task definition..."
sed -e "s|{{ACCOUNT_ID}}|${ACCOUNT_ID}|g" \
    -e "s|{{AWS_REGION}}|${AWS_REGION}|g" \
    -e "s|{{IMAGE_URI}}|${IMAGE_URI}|g" \
    -e "s|{{DB_USERNAME_SECRET_ARN}}|${DB_USERNAME_SECRET_ARN}|g" \
    -e "s|{{DB_PASSWORD_SECRET_ARN}}|${DB_PASSWORD_SECRET_ARN}|g" \
    ecs/task-definition.json > "task-definition-resolved.json"
echo "Task definition generated."
echo ""

# Register task definition
echo "Registering task definition..."
TASK_DEF_ARN=$(aws ecs register-task-definition --cli-input-json file://task-definition-resolved.json --region "$AWS_REGION" --query 'taskDefinition.taskDefinitionArn' --output text)
echo "Task Definition ARN: ${TASK_DEF_ARN}"
echo ""

# Generate service definition
echo "Generating service definition..."
if [ -n "$TARGET_GROUP_ARN" ]; then
    sed -e "s|{{CLUSTER_NAME}}|${CLUSTER_NAME}|g" \
        -e "s|{{SUBNET_1}}|${SUBNET_1}|g" \
        -e "s|{{SUBNET_2}}|${SUBNET_2}|g" \
        -e "s|{{SECURITY_GROUP}}|${SECURITY_GROUP}|g" \
        -e "s|{{TARGET_GROUP_ARN}}|${TARGET_GROUP_ARN}|g" \
        ecs/service-definition.json > "service-definition-resolved.json"
else
    # Remove loadBalancers section since no LB was requested
    sed -e "s|{{CLUSTER_NAME}}|${CLUSTER_NAME}|g" \
        -e "s|{{SUBNET_1}}|${SUBNET_1}|g" \
        -e "s|{{SUBNET_2}}|${SUBNET_2}|g" \
        -e "s|{{SECURITY_GROUP}}|${SECURITY_GROUP}|g" \
        ecs/service-definition.json > "service-definition-temp.json"
    # Remove the loadBalancers section using python
    python3 -c "
import json, sys
with open('service-definition-temp.json') as f:
    data = json.load(f)
if 'loadBalancers' in data:
    del data['loadBalancers']
if 'healthCheckGracePeriodSeconds' in data:
    del data['healthCheckGracePeriodSeconds']
with open('service-definition-resolved.json', 'w') as f:
    json.dump(data, f, indent=2)
"
fi
echo "Service definition generated."
echo ""

# Check if service exists
echo "Checking if service '${SERVICE_NAME}' exists..."
SERVICE_EXISTS=$(aws ecs describe-services --cluster "$CLUSTER_NAME" --services "$SERVICE_NAME" --region "$AWS_REGION" --query 'services[0].serviceName' --output text 2>/dev/null || echo "")

if [ -z "$SERVICE_EXISTS" ]; then
    echo "Creating ECS service '${SERVICE_NAME}'..."
    aws ecs create-service --cli-input-json file://service-definition-resolved.json --region "$AWS_REGION"
    echo "Service created."
else
    echo "Updating ECS service '${SERVICE_NAME}'..."
    aws ecs update-service --cluster "$CLUSTER_NAME" --service "$SERVICE_NAME" --task-definition "$TASK_DEF_ARN" --desired-count 2 --region "$AWS_REGION"
    echo "Service updated."
fi
echo ""

# Wait for service to be stable
echo "Waiting for service to become stable..."
aws ecs wait services-stable --cluster "$CLUSTER_NAME" --services "$SERVICE_NAME" --region "$AWS_REGION"
echo "Service is stable."
echo ""

# Show service details
echo "=== Deployment Summary ==="
aws ecs describe-services --cluster "$CLUSTER_NAME" --services "$SERVICE_NAME" --region "$AWS_REGION" --query 'services[0].{RunningCount:runningCount, DesiredCount:desiredCount, Status:status}' --output table
echo ""

if [ -n "$ALB_DNS" ]; then
    echo "Load Balancer DNS: ${ALB_DNS}"
fi
echo "Log Group: /ecs/rleks"
echo ""
echo "=== Troubleshooting ==="
echo "- If tasks fail to start, check CloudWatch Logs at /ecs/rleks"
echo "- If tasks fail to pull image, verify ECR permissions and execution role"
echo "- If health checks fail, ensure the application exposes /actuator/health on port 8080"
echo "- If credentials are missing, verify Secrets Manager ARNs in the task definition"
echo "- For network issues, check security group rules allow traffic on port 8080"
echo "- For CPU/memory errors, adjust cpu and memory in the task definition"
