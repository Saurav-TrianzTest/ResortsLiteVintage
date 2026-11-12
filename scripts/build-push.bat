@echo off
setlocal enabledelayedexpansion

echo === ResortsLite (RLEKS) Build and Push Script ===
echo.

echo 1. Target Platform: AWS ECR
echo.
set /p AWS_REGION="Enter AWS region (e.g., us-east-1): "
set /p ECR_REPO="Enter ECR repository name: "
set /p IMAGE_TAG="Enter image tag (leave empty for 'latest'): "

if "!IMAGE_TAG!"=="" (
    set IMAGE_TAG=latest
)

set PROJECT_NAME=ResortsLite
for /f "delims=" %%i in ('powershell -Command "(('!PROJECT_NAME!' -creplace '[^a-z0-9]', '-').Trim('-')).ToLower()"') do set IMAGE_NAME=%%i
set REGISTRY_URL=!AWS_ACCOUNT_ID!.dkr.ecr.!AWS_REGION!.amazonaws.com
set FULL_IMAGE_NAME=!REGISTRY_URL!/!ECR_REPO!:!IMAGE_TAG!

echo.
echo Image: !FULL_IMAGE_NAME!
echo.

echo 2. Retrieving AWS account ID...
for /f "delims=" %%i in ('aws sts get-caller-identity --query Account --output text') do set AWS_ACCOUNT_ID=%%i
set REGISTRY_URL=!AWS_ACCOUNT_ID!.dkr.ecr.!AWS_REGION!.amazonaws.com
set FULL_IMAGE_NAME=!REGISTRY_URL!/!ECR_REPO!:!IMAGE_TAG!

echo Account ID: !AWS_ACCOUNT_ID!
echo Registry URL: !REGISTRY_URL!
echo.

echo 3. Logging in to Amazon ECR...
aws ecr get-login-password --region !AWS_REGION! | docker login --username AWS --password-stdin !REGISTRY_URL!
if !ERRORLEVEL! neq 0 (
    echo ECR login failed
    exit /b 1
)
echo Login successful.
echo.

echo 4. Checking if ECR repository exists...
aws ecr describe-repositories --repository-names !ECR_REPO! --region !AWS_REGION! >nul 2>&1
if !ERRORLEVEL! neq 0 (
    echo Creating ECR repository '!ECR_REPO!'...
    aws ecr create-repository --repository-name !ECR_REPO! --region !AWS_REGION!
    if !ERRORLEVEL! neq 0 (
        echo ECR repository creation failed
        exit /b 1
    )
    echo Repository created.
) else (
    echo Repository '!ECR_REPO!' already exists.
)
echo.

echo 5. Building Docker image...
docker build -f Dockerfile -t !FULL_IMAGE_NAME! .
if !ERRORLEVEL! neq 0 (
    echo Docker build failed
    exit /b 1
)
echo Build complete.
echo.

echo 6. Pushing image to ECR...
docker push !FULL_IMAGE_NAME!
if !ERRORLEVEL! neq 0 (
    echo Docker push failed
    exit /b 1
)
echo Push complete.
echo.

echo === Done ===
echo Image pushed to: !FULL_IMAGE_NAME!
