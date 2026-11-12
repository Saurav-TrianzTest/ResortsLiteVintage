@echo off
setlocal enabledelayedexpansion

echo === ResortsLite Deploy to Azure AKS Script ===

set NAMESPACE=resortslite

REM Ask for Azure cluster details
set /p RESOURCE_GROUP="Enter Azure resource group: "
set /p CLUSTER_NAME="Enter AKS cluster name: "

echo.
echo Configuring kubectl for AKS cluster: !CLUSTER_NAME!
az aks get-credentials --resource-group "!RESOURCE_GROUP!" --name "!CLUSTER_NAME!"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to configure kubectl
    exit /b 1
)

echo.
echo Checking cluster connectivity...
kubectl cluster-info
if !ERRORLEVEL! neq 0 (
    echo ERROR: Cannot connect to AKS cluster
    exit /b 1
)

REM Ask for image URI
set /p IMAGE_URI="Enter full image URI (e.g., myacr.azurecr.io/resortslite:latest): "

REM Ask for environment variables
echo.
set /p REDIS_HOST="Enter value for REDIS_HOST (or press Enter to skip): "
set /p PAYMENT_API="Enter value for PAYMENT_API (or press Enter to skip): "

REM Ask for credentials (without echoing)
echo.
set /p REDIS_PASSWORD="Enter value for REDIS_PASSWORD (or press Enter to skip): "

REM Apply namespace
echo.
echo Applying namespace...
kubectl apply -f kubernetes/namespace.yaml
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to apply namespace
    exit /b 1
)

REM Create Secret for credentials
echo.
echo Creating Kubernetes Secret...
kubectl create secret generic resortslite-secrets -n !NAMESPACE! --from-literal=REDIS_PASSWORD="!REDIS_PASSWORD!" --dry-run=client -o yaml | kubectl apply -f -
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to create secret
    exit /b 1
)

REM Replace placeholders in deployment.yaml
echo.
echo Deploying application...

REM Create a temporary copy for substitution
copy kubernetes\deployment.yaml "%TEMP%\deployment-substituted.yaml" >nul

powershell -Command "(gc '%TEMP%\deployment-substituted.yaml') -replace '{{NAMESPACE}}', '!NAMESPACE!' | Out-File -Encoding UTF8 '%TEMP%\deployment-substituted.yaml'"
powershell -Command "(gc '%TEMP%\deployment-substituted.yaml') -replace '{{IMAGE_URI}}', '!IMAGE_URI!' | Out-File -Encoding UTF8 '%TEMP%\deployment-substituted.yaml'"
powershell -Command "(gc '%TEMP%\deployment-substituted.yaml') -replace '{{REDIS_HOST}}', '!REDIS_HOST!' | Out-File -Encoding UTF8 '%TEMP%\deployment-substituted.yaml'"
powershell -Command "(gc '%TEMP%\deployment-substituted.yaml') -replace '{{PAYMENT_API}}', '!PAYMENT_API!' | Out-File -Encoding UTF8 '%TEMP%\deployment-substituted.yaml'"

kubectl apply -f "%TEMP%\deployment-substituted.yaml"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to apply deployment
    del "%TEMP%\deployment-substituted.yaml"
    exit /b 1
)
del "%TEMP%\deployment-substituted.yaml"

REM Apply service and ingress with namespace substitution
copy kubernetes\service.yaml "%TEMP%\service-substituted.yaml" >nul
powershell -Command "(gc '%TEMP%\service-substituted.yaml') -replace '{{NAMESPACE}}', '!NAMESPACE!' | Out-File -Encoding UTF8 '%TEMP%\service-substituted.yaml'"
kubectl apply -f "%TEMP%\service-substituted.yaml"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to apply service
    del "%TEMP%\service-substituted.yaml"
    exit /b 1
)
del "%TEMP%\service-substituted.yaml"

copy kubernetes\ingress.yaml "%TEMP%\ingress-substituted.yaml" >nul
powershell -Command "(gc '%TEMP%\ingress-substituted.yaml') -replace '{{NAMESPACE}}', '!NAMESPACE!' | Out-File -Encoding UTF8 '%TEMP%\ingress-substituted.yaml'"
kubectl apply -f "%TEMP%\ingress-substituted.yaml"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to apply ingress
    del "%TEMP%\ingress-substituted.yaml"
    exit /b 1
)
del "%TEMP%\ingress-substituted.yaml"

REM Wait for deployment
echo.
echo Waiting for deployment to be ready...
kubectl rollout status deployment/resortslite -n !NAMESPACE!
if !ERRORLEVEL! neq 0 (
    echo ERROR: Deployment failed
    echo Rollback with: kubectl rollout undo deployment/resortslite -n !NAMESPACE!
    exit /b 1
)

REM Show status
echo.
echo === Deployment complete ===
kubectl get pods,svc,ingress -n !NAMESPACE!
echo.
echo Application URL: https://resortslite.example.com
echo.
echo If something went wrong, rollback with:
echo   kubectl rollout undo deployment/resortslite -n !NAMESPACE!

endlocal
exit /b 0
