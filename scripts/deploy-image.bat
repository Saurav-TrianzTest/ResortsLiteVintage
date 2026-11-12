@echo off
setlocal enabledelayedexpansion

set PROJECT_NAME=ResortsLite
set NAME=%PROJECT_NAME%
:: Sanitize NAME: lowercase, replace non-alphanumeric with hyphen
for /f "delims=" %%i in ('powershell -command "$env:PROJECT_NAME'.ToLower() -creplace '[^a-z0-9]', '-'"') do set NAME=%%i
:: Remove leading/trailing hyphens
:trim_start
if "%NAME:~0,1%"=="-" set NAME=%NAME:~1% & goto trim_start
:trim_end
if "%NAME:~-1%"=="-" set NAME=%NAME:~0,-1% & goto trim_end

echo === ResortsLite GKE Deployment Script ===
echo.

set /p GCP_PROJECT="Enter GCP Project ID: "
set /p GCP_ZONE="Enter GCP Zone (e.g., us-central1-a): "
set /p CLUSTER_NAME="Enter GKE Cluster Name: "
set /p IMAGE_URI="Enter Image URI (full path with registry and tag): "

echo.
echo Configuring kubectl for GKE cluster...
gcloud container clusters get-credentials "!CLUSTER_NAME!" --zone "!GCP_ZONE!" --project "!GCP_PROJECT!"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to configure kubectl for GKE cluster
    exit /b 1
)

echo.
echo Verifying cluster connectivity...
kubectl cluster-info
if !ERRORLEVEL! neq 0 (
    echo ERROR: kubectl cluster-info failed
    exit /b 1
)

echo.
echo Enter values for environment variables (press Enter to skip):
set /p PAYMENT_API_URL="Enter value for PAYMENT_API_URL (or press Enter to skip): "
set /p INVENTORY_API_URL="Enter value for INVENTORY_API_URL (or press Enter to skip): "
set /p NOTIFICATION_API_URL="Enter value for NOTIFICATION_API_URL (or press Enter to skip): "

echo.
echo Enter credential values (not echoed):
set /p DB_HOST="Enter DB_HOST: "
set /p DB_USER="Enter DB_USER: "
set /p DB_PASS="Enter DB_PASS: "
set /p REDIS_HOST="Enter REDIS_HOST: "
set /p REDIS_PORT="Enter REDIS_PORT: "

echo.
echo Creating Kubernetes Secret...
kubectl create secret generic !NAME!-secrets -n !NAME! ^
    --from-literal=DB_HOST="!DB_HOST!" ^
    --from-literal=DB_USER="!DB_USER!" ^
    --from-literal=DB_PASS="!DB_PASS!" ^
    --from-literal=REDIS_HOST="!REDIS_HOST!" ^
    --from-literal=REDIS_PORT="!REDIS_PORT!" ^
    --dry-run=client -o yaml | kubectl apply -f -
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to create Kubernetes Secret
    exit /b 1
)

echo.
echo Applying namespace...
kubectl apply -f kubernetes/namespace.yaml
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to apply namespace
    exit /b 1
)

echo.
echo Deploying application...
:: Replace placeholders in deployment.yaml
powershell -command "(Get-Content kubernetes/deployment.yaml) -replace '{{IMAGE_URI}}', '!IMAGE_URI!' | Set-Content kubernetes/deployment.yaml"
if "!PAYMENT_API_URL!"=="" set PAYMENT_API_URL=http://payment-service:9090/charge
if "!INVENTORY_API_URL!"=="" set INVENTORY_API_URL=http://inventory-service:8081/rooms
if "!NOTIFICATION_API_URL!"=="" set NOTIFICATION_API_URL=http://notify-service:7070/send
powershell -command "(Get-Content kubernetes/deployment.yaml) -replace '{{PAYMENT_API_URL}}', '!PAYMENT_API_URL!' | Set-Content kubernetes/deployment.yaml"
powershell -command "(Get-Content kubernetes/deployment.yaml) -replace '{{INVENTORY_API_URL}}', '!INVENTORY_API_URL!' | Set-Content kubernetes/deployment.yaml"
powershell -command "(Get-Content kubernetes/deployment.yaml) -replace '{{NOTIFICATION_API_URL}}', '!NOTIFICATION_API_URL!' | Set-Content kubernetes/deployment.yaml"

kubectl apply -f kubernetes/deployment.yaml
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to apply deployment
    exit /b 1
)
kubectl apply -f kubernetes/service.yaml
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to apply service
    exit /b 1
)
kubectl apply -f kubernetes/ingress.yaml
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to apply ingress
    exit /b 1
)

echo.
echo Waiting for deployment rollout...
kubectl rollout status deployment/!NAME! -n !NAME!
if !ERRORLEVEL! neq 0 (
    echo ERROR: Deployment rollout failed
    exit /b 1
)

echo.
echo === Deployment Status ===
kubectl get pods,svc,ingress -n !NAME!

echo.
echo === Application URL ===
echo http://!NAME!.example.com

echo.
echo === Deployment complete ===
echo To rollback: kubectl rollout undo deployment/!NAME! -n !NAME!

endlocal
