@echo off & setlocal enabledelayedexpansion

set "APP_NAME=resortslite"
set "NAMESPACE=resortslite"
set "SCRIPT_DIR=%~dp0"

echo === Deploy !APP_NAME! to AWS EKS ===
set /p AWS_REGION="AWS region (e.g. us-east-1): "
set /p CLUSTER_NAME="EKS cluster name: "
set /p IMAGE_URI="Docker image URI (registry/repo:tag): "
if "!AWS_REGION!"=="" (echo AWS region is required & exit /b 1)
if "!CLUSTER_NAME!"=="" (echo Cluster name is required & exit /b 1)
if "!IMAGE_URI!"=="" (echo Image URI is required & exit /b 1)

set "REDIS_HOST=localhost"
set "REDIS_PORT=6379"
set "REDIS_PASSWORD="
set "REDIS_SSL_ENABLED=false"
set "SESSION_REDIS_NAMESPACE=resortslite:session"
set "BOOKING_CACHE_KEY_PREFIX=resortslite:booking:"
set "BOOKING_CACHE_TTL_SECONDS=3600"
set /p REDIS_HOST="Enter value for REDIS_HOST (or press Enter to skip) [localhost]: "
set /p REDIS_PORT="Enter value for REDIS_PORT (or press Enter to skip) [6379]: "
set /p REDIS_PASSWORD="Enter value for REDIS_PASSWORD (or press Enter to skip): "
set /p REDIS_SSL_ENABLED="Enter value for REDIS_SSL_ENABLED (or press Enter to skip) [false]: "
set /p SESSION_REDIS_NAMESPACE="Enter value for SESSION_REDIS_NAMESPACE (or press Enter to skip) [resortslite:session]: "
set /p BOOKING_CACHE_KEY_PREFIX="Enter value for BOOKING_CACHE_KEY_PREFIX (or press Enter to skip) [resortslite:booking:]: "
set /p BOOKING_CACHE_TTL_SECONDS="Enter value for BOOKING_CACHE_TTL_SECONDS (or press Enter to skip) [3600]: "

rem Work on a temp copy so the template manifests keep their placeholders
set "WORK_DIR=%TEMP%\resortslite-k8s-%RANDOM%"
mkdir "!WORK_DIR!"
xcopy /E /I /Y /Q "!SCRIPT_DIR!..\kubernetes" "!WORK_DIR!\kubernetes" >nul
if !ERRORLEVEL! neq 0 (
    echo Failed to copy manifests
    exit /b 1
)

set "DEP=!WORK_DIR!\kubernetes\deployment.yaml"
powershell -NoProfile -Command "$p=$env:DEP; $c=Get-Content -Raw $p; $c=$c.Replace('{{IMAGE_URI}}',$env:IMAGE_URI).Replace('{{REDIS_HOST}}',$env:REDIS_HOST).Replace('{{REDIS_PORT}}',$env:REDIS_PORT).Replace('{{REDIS_SSL_ENABLED}}',$env:REDIS_SSL_ENABLED).Replace('{{SESSION_REDIS_NAMESPACE}}',$env:SESSION_REDIS_NAMESPACE).Replace('{{BOOKING_CACHE_KEY_PREFIX}}',$env:BOOKING_CACHE_KEY_PREFIX).Replace('{{BOOKING_CACHE_TTL_SECONDS}}',$env:BOOKING_CACHE_TTL_SECONDS); Set-Content -Path $p -Value $c -NoNewline"
if !ERRORLEVEL! neq 0 (
    echo Failed to update manifests
    exit /b 1
)

echo Configuring kubectl...
aws eks update-kubeconfig --region !AWS_REGION! --name !CLUSTER_NAME!
if !ERRORLEVEL! neq 0 (
    echo Failed to configure kubectl
    exit /b 1
)

echo Verifying cluster connectivity...
kubectl cluster-info
if !ERRORLEVEL! neq 0 (
    echo Cannot connect to cluster
    exit /b 1
)

echo Applying manifests...
kubectl apply -f "!WORK_DIR!\kubernetes\namespace.yaml"
if !ERRORLEVEL! neq 0 (
    echo Namespace apply failed
    exit /b 1
)

kubectl create secret generic resortslite-secrets -n !NAMESPACE! --from-literal=REDIS_PASSWORD="!REDIS_PASSWORD!" --dry-run=client -o yaml > "!WORK_DIR!\secret.yaml"
kubectl apply -f "!WORK_DIR!\secret.yaml"
if !ERRORLEVEL! neq 0 (
    echo Secret apply failed
    exit /b 1
)

kubectl apply -f "!WORK_DIR!\kubernetes\deployment.yaml"
if !ERRORLEVEL! neq 0 (
    echo Deployment apply failed
    exit /b 1
)
kubectl apply -f "!WORK_DIR!\kubernetes\service.yaml"
if !ERRORLEVEL! neq 0 (
    echo Service apply failed
    exit /b 1
)
kubectl apply -f "!WORK_DIR!\kubernetes\ingress.yaml"
if !ERRORLEVEL! neq 0 (
    echo Ingress apply failed
    exit /b 1
)

echo Waiting for rollout...
kubectl rollout status deployment/!APP_NAME! -n !NAMESPACE! --timeout=300s
if !ERRORLEVEL! neq 0 (
    echo Rollout failed. To roll back run:
    echo   kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
    exit /b 1
)

kubectl get pods,svc,ingress -n !NAMESPACE!
echo Get the application URL with: kubectl get ingress !APP_NAME!-ingress -n !NAMESPACE!
rmdir /S /Q "!WORK_DIR!" >nul 2>&1
endlocal
