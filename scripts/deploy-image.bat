@echo off
setlocal enabledelayedexpansion

echo === ResortsLite (RLEKS) ECS Fargate Deployment Script ===
echo.

set /p AWS_REGION="Enter AWS region (e.g., us-east-1): "

echo Retrieving AWS account ID...
for /f "delims=" %%i in ('aws sts get-caller-identity --query Account --output text') do set ACCOUNT_ID=%%i
echo Account ID: !ACCOUNT_ID!
echo.

set /p CLUSTER_NAME="Enter ECS cluster name: "
set /p VPC_ID="Enter VPC ID: "
set /p SUBNETS="Enter subnet IDs (comma-separated, at least two): "
set /p SECURITY_GROUP="Enter security group ID: "

REM Parse subnets
for /f "tokens=1,2 delims=," %%a in ("!SUBNETS!") do (
    set SUBNET_1=%%a
    set SUBNET_2=%%b
)

set /p IMAGE_URI="Enter full image URI (e.g., 123456789.dkr.ecr.us-east-1.amazonaws.com/rleks:latest): "

REM Create cluster if it doesn't exist
echo.
echo Checking if ECS cluster '!CLUSTER_NAME!' exists...
aws ecs describe-clusters --clusters !CLUSTER_NAME! --region !AWS_REGION! 2>nul | findstr /C:"clusterName" >nul
if !ERRORLEVEL! equ 0 (
    echo Cluster already exists.
) else (
    echo Creating ECS cluster '!CLUSTER_NAME!'...
    aws ecs create-cluster --cluster-name !CLUSTER_NAME! --region !AWS_REGION!
    echo Cluster created.
)
echo.

set /p NEED_LB="Do you need a load balancer for this service? (y/n): "

set SERVICE_NAME=rleks-service
set TARGET_GROUP_ARN=

if /I "!NEED_LB!"=="y" (
    echo.
    echo Creating Application Load Balancer and target group...
    
    REM Create security group for ALB
    for /f "delims=" %%i in ('aws ec2 create-security-group --group-name "rleks-alb-sg" --description "Security group for RLEKS ALB" --vpc-id !VPC_ID! --region !AWS_REGION! --query "GroupId" --output text') do set ALB_SG=%%i
    echo ALB Security Group: !ALB_SG!
    
    REM Allow HTTP traffic on port 8080
    aws ec2 authorize-security-group-ingress --group-id !ALB_SG! --protocol tcp --port 8080 --cidr 0.0.0.0/0 --region !AWS_REGION!
    
    REM Create target group
    for /f "delims=" %%i in ('aws elbv2 create-target-group --name "rleks-tg" --protocol HTTP --port 8080 --vpc-id !VPC_ID! --target-type ip --health-check-path "/actuator/health" --health-check-port "8080" --region !AWS_REGION! --query "TargetGroups[0].TargetGroupArn" --output text') do set TARGET_GROUP_ARN=%%i
    echo Target Group ARN: !TARGET_GROUP_ARN!
    
    REM Create ALB
    for /f "delims=" %%i in ('aws elbv2 create-load-balancer --name "rleks-alb" --subnets !SUBNET_1! !SUBNET_2! --security-groups !ALB_SG! --scheme internet-facing --type application --region !AWS_REGION! --query "LoadBalancers[0].LoadBalancerArn" --output text') do set ALB_ARN=%%i
    echo ALB ARN: !ALB_ARN!
    
    REM Create listener
    aws elbv2 create-listener --load-balancer-arn !ALB_ARN! --protocol HTTP --port 80 --default-actions "Type=forward,TargetGroupArn=!TARGET_GROUP_ARN!" --region !AWS_REGION!
    echo Listener created on port 80.
    
    REM Get ALB DNS name
    for /f "delims=" %%i in ('aws elbv2 describe-load-balancers --load-balancer-arns !ALB_ARN! --region !AWS_REGION! --query "LoadBalancers[0].DNSName" --output text') do set ALB_DNS=%%i
    echo ALB DNS: !ALB_DNS!
    echo.
) else (
    echo No load balancer requested.
    echo.
)

REM Handle credentials
echo Enter credentials for the application:
echo.
set /p DB_USERNAME_VALUE="Enter DB_USERNAME: "
set /p DB_PASSWORD_VALUE="Enter DB_PASSWORD: "
echo.

REM Store credentials in Secrets Manager
echo Storing credentials in AWS Secrets Manager...

set DB_USERNAME_SECRET_NAME=rleks/DB_USERNAME
set DB_PASSWORD_SECRET_NAME=rleks/DB_PASSWORD

aws secretsmanager describe-secret --secret-id !DB_USERNAME_SECRET_NAME! --region !AWS_REGION! >nul 2>&1
if !ERRORLEVEL! equ 0 (
    echo Updating secret '!DB_USERNAME_SECRET_NAME!'...
    aws secretsmanager put-secret-value --secret-id !DB_USERNAME_SECRET_NAME! --secret-string !DB_USERNAME_VALUE! --region !AWS_REGION!
) else (
    echo Creating secret '!DB_USERNAME_SECRET_NAME!'...
    aws secretsmanager create-secret --name !DB_USERNAME_SECRET_NAME! --secret-string !DB_USERNAME_VALUE! --region !AWS_REGION!
)
for /f "delims=" %%i in ('aws secretsmanager describe-secret --secret-id !DB_USERNAME_SECRET_NAME! --region !AWS_REGION! --query "ARN" --output text') do set DB_USERNAME_SECRET_ARN=%%i
echo DB_USERNAME secret ARN: !DB_USERNAME_SECRET_ARN!

aws secretsmanager describe-secret --secret-id !DB_PASSWORD_SECRET_NAME! --region !AWS_REGION! >nul 2>&1
if !ERRORLEVEL! equ 0 (
    echo Updating secret '!DB_PASSWORD_SECRET_NAME!'...
    aws secretsmanager put-secret-value --secret-id !DB_PASSWORD_SECRET_NAME! --secret-string !DB_PASSWORD_VALUE! --region !AWS_REGION!
) else (
    echo Creating secret '!DB_PASSWORD_SECRET_NAME!'...
    aws secretsmanager create-secret --name !DB_PASSWORD_SECRET_NAME! --secret-string !DB_PASSWORD_VALUE! --region !AWS_REGION!
)
for /f "delims=" %%i in ('aws secretsmanager describe-secret --secret-id !DB_PASSWORD_SECRET_NAME! --region !AWS_REGION! --query "ARN" --output text') do set DB_PASSWORD_SECRET_ARN=%%i
echo DB_PASSWORD secret ARN: !DB_PASSWORD_SECRET_ARN!
echo.

REM Create log group if it doesn't exist
echo Checking if log group '/ecs/rleks' exists...
aws logs describe-log-groups --log-group-name-prefix "/ecs/rleks" --region !AWS_REGION! --query "logGroups[?logGroupName=='/ecs/rleks'].logGroupName" --output text >nul 2>&1
if !ERRORLEVEL! neq 0 (
    echo Creating log group '/ecs/rleks'...
    aws logs create-log-group --log-group-name "/ecs/rleks" --region !AWS_REGION!
    echo Log group created.
) else (
    echo Log group already exists.
)
echo.

REM Replace placeholders in task definition
echo Generating task definition...
REM Use PowerShell for JSON processing since Windows batch has no sed
powershell -Command "(Get-Content ecs/task-definition.json -Raw) -replace '{{ACCOUNT_ID}}', '!ACCOUNT_ID!' -replace '{{AWS_REGION}}', '!AWS_REGION!' -replace '{{IMAGE_URI}}', '!IMAGE_URI!' -replace '{{DB_USERNAME_SECRET_ARN}}', '!DB_USERNAME_SECRET_ARN!' -replace '{{DB_PASSWORD_SECRET_ARN}}', '!DB_PASSWORD_SECRET_ARN!'" > "task-definition-resolved.json"
echo Task definition generated.
echo.

REM Register task definition
echo Registering task definition...
for /f "delims=" %%i in ('aws ecs register-task-definition --cli-input-json file://task-definition-resolved.json --region !AWS_REGION! --query "taskDefinition.taskDefinitionArn" --output text') do set TASK_DEF_ARN=%%i
echo Task Definition ARN: !TASK_DEF_ARN!
echo.

REM Generate service definition
echo Generating service definition...
if defined TARGET_GROUP_ARN (
    powershell -Command "(Get-Content ecs/service-definition.json -Raw) -replace '{{CLUSTER_NAME}}', '!CLUSTER_NAME!' -replace '{{SUBNET_1}}', '!SUBNET_1!' -replace '{{SUBNET_2}}', '!SUBNET_2!' -replace '{{SECURITY_GROUP}}', '!SECURITY_GROUP!' -replace '{{TARGET_GROUP_ARN}}', '!TARGET_GROUP_ARN!'" > "service-definition-resolved.json"
) else (
    powershell -Command "$d = (Get-Content ecs/service-definition.json -Raw) | ConvertFrom-Json; $d.PSObject.Properties.Remove('loadBalancers'); $d.PSObject.Properties.Remove('healthCheckGracePeriodSeconds'); $d | ConvertTo-Json -Depth 10" > "service-definition-resolved.json"
)
echo Service definition generated.
echo.

REM Check if service exists
echo Checking if service '!SERVICE_NAME!' exists...
aws ecs describe-services --cluster !CLUSTER_NAME! --services !SERVICE_NAME! --region !AWS_REGION! --query "services[0].serviceName" --output text >nul 2>&1
if !ERRORLEVEL! neq 0 (
    echo Creating ECS service '!SERVICE_NAME!'...
    aws ecs create-service --cli-input-json file://service-definition-resolved.json --region !AWS_REGION!
    echo Service created.
) else (
    echo Updating ECS service '!SERVICE_NAME!'...
    aws ecs update-service --cluster !CLUSTER_NAME! --service !SERVICE_NAME! --task-definition !TASK_DEF_ARN! --desired-count 2 --region !AWS_REGION!
    echo Service updated.
)
echo.

REM Wait for service to be stable
echo Waiting for service to become stable...
aws ecs wait services-stable --cluster !CLUSTER_NAME! --services !SERVICE_NAME! --region !AWS_REGION!
echo Service is stable.
echo.

REM Show service details
echo === Deployment Summary ===
aws ecs describe-services --cluster !CLUSTER_NAME! --services !SERVICE_NAME! --region !AWS_REGION! --query "services[0].{RunningCount:runningCount, DesiredCount:desiredCount, Status:status}" --output table
echo.

if defined ALB_DNS (
    echo Load Balancer DNS: !ALB_DNS!
)
echo Log Group: /ecs/rleks
echo.
echo === Troubleshooting ===
echo - If tasks fail to start, check CloudWatch Logs at /ecs/rleks
echo - If tasks fail to pull image, verify ECR permissions and execution role
echo - If health checks fail, ensure the application exposes /actuator/health on port 8080
echo - If credentials are missing, verify Secrets Manager ARNs in the task definition
echo - For network issues, check security group rules allow traffic on port 8080
echo - For CPU/memory errors, adjust cpu and memory in the task definition
