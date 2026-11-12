@echo off
setlocal enabledelayedexpansion

echo === ResortsLite Build and Push Script ===

set PROJECT_NAME=ResortsLite

REM Sanitize project name for image name using PowerShell
for /f %%i in ('powershell -Command "$n = '%PROJECT_NAME%'; ($n.ToLower() -replace '[^a-z0-9]', '-').Trim('-')"') do set IMAGE_NAME=%%i

echo.
echo Choose target registry:
echo   1) Azure ACR
echo   2) Docker Hub
set /p REGISTRY_CHOICE="Enter choice (1 or 2): "

if "!REGISTRY_CHOICE!"=="1" (
    set /p ACR_NAME="Enter ACR name (e.g., myacr): "
    set /p IMAGE_TAG="Enter image tag (press Enter for 'latest'): "
    if "!IMAGE_TAG!"=="" set IMAGE_TAG=latest
    set FULL_IMAGE_NAME=!ACR_NAME!.azurecr.io/!IMAGE_NAME!:!IMAGE_TAG!
    echo.
    echo Logging in to Azure ACR: !ACR_NAME!
    az acr login --name !ACR_NAME!
    if !ERRORLEVEL! neq 0 (
        echo ERROR: ACR login failed
        exit /b 1
    )
) else if "!REGISTRY_CHOICE!"=="2" (
    set /p DOCKER_USERNAME="Enter Docker Hub username: "
    set /p DOCKER_PASSWORD="Enter Docker Hub password: "
    set /p IMAGE_TAG="Enter image tag (press Enter for 'latest'): "
    if "!IMAGE_TAG!"=="" set IMAGE_TAG=latest
    set FULL_IMAGE_NAME=!DOCKER_USERNAME!/!IMAGE_NAME!:!IMAGE_TAG!
    echo.
    echo Logging in to Docker Hub
    echo !DOCKER_PASSWORD! | docker login --username !DOCKER_USERNAME! --password-stdin
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Docker Hub login failed
        exit /b 1
    )
) else (
    echo ERROR: Invalid choice
    exit /b 1
)

echo.
echo Building image: !FULL_IMAGE_NAME!
docker build -f Dockerfile -t !FULL_IMAGE_NAME! .
if !ERRORLEVEL! neq 0 (
    echo ERROR: Docker build failed
    exit /b 1
)

echo.
echo Pushing image: !FULL_IMAGE_NAME!
docker push !FULL_IMAGE_NAME!
if !ERRORLEVEL! neq 0 (
    echo ERROR: Docker push failed
    exit /b 1
)

echo.
echo === Build and push complete ===
echo Image: !FULL_IMAGE_NAME!

endlocal
