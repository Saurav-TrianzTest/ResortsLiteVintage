@echo off
setlocal enabledelayedexpansion

set PROJECT_NAME=ResortsLite

echo === ResortsLite Build and Push Script ===
echo.

echo Select target platform:
echo 1. Google Artifact Registry ^(GCP^)
echo 2. Docker Hub
set /p PLATFORM_CHOICE="Enter choice (1 or 2): "

set IMAGE_NAME=%PROJECT_NAME%
:: Sanitize IMAGE_NAME: lowercase, replace non-alphanumeric with hyphen
for /f "delims=" %%i in ('powershell -command "$env:PROJECT_NAME'.ToLower() -creplace '[^a-z0-9]', '-'"') do set IMAGE_NAME=%%i
:: Remove leading/trailing hyphens
:trim_start
if "%IMAGE_NAME:~0,1%"=="-" set IMAGE_NAME=%IMAGE_NAME:~1% & goto trim_start
:trim_end
if "%IMAGE_NAME:~-1%"=="-" set IMAGE_NAME=%IMAGE_NAME:~0,-1% & goto trim_end

if "%PLATFORM_CHOICE%"=="1" (
    echo.
    echo --- Google Artifact Registry ---
    set /p GCP_REGION="Enter GCP Region (e.g., us-central1): "
    set /p GCP_PROJECT="Enter GCP Project ID: "
    set /p GCP_REPO="Enter Artifact Registry Repository Name: "
    set /p IMAGE_TAG="Enter IMAGE_TAG (press Enter for latest): "

    if "!IMAGE_TAG!"=="" set IMAGE_TAG=latest

    :: Sanitize IMAGE_TAG
    for /f "delims=" %%i in ('powershell -command "'!IMAGE_TAG!' -creplace '[^a-z0-9.-]', '-'"') do set IMAGE_TAG=%%i
    :trim_tag_start
    if "!IMAGE_TAG:~0,1!"=="-" set IMAGE_TAG=!IMAGE_TAG:~1! & goto trim_tag_start
    :trim_tag_end
    if "!IMAGE_TAG:~-1!"=="-" set IMAGE_TAG=!IMAGE_TAG:~0,-1! & goto trim_tag_end

    set REGISTRY=!GCP_REGION!-docker.pkg.dev
    set FULL_IMAGE_NAME=!REGISTRY!/!GCP_PROJECT!/!GCP_REPO!/!IMAGE_NAME!:!IMAGE_TAG!

    echo.
    echo Authenticating with Google Artifact Registry...
    gcloud auth configure-docker "!REGISTRY!"
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Artifact Registry login failed
        exit /b 1
    )

) else if "%PLATFORM_CHOICE%"=="2" (
    echo.
    echo --- Docker Hub ---
    set /p DOCKER_USERNAME="Enter Docker Hub Username: "
    set /p DOCKER_PASSWORD="Enter Docker Hub Password: "
    set /p IMAGE_TAG="Enter IMAGE_TAG (press Enter for latest): "

    if "!IMAGE_TAG!"=="" set IMAGE_TAG=latest

    :: Sanitize IMAGE_TAG
    for /f "delims=" %%i in ('powershell -command "'!IMAGE_TAG!' -creplace '[^a-z0-9.-]', '-'"') do set IMAGE_TAG=%%i
    :trim_tag_start2
    if "!IMAGE_TAG:~0,1!"=="-" set IMAGE_TAG=!IMAGE_TAG:~1! & goto trim_tag_start2
    :trim_tag_end2
    if "!IMAGE_TAG:~-1!"=="-" set IMAGE_TAG=!IMAGE_TAG:~0,-1! & goto trim_tag_end2

    set FULL_IMAGE_NAME=!DOCKER_USERNAME!/!IMAGE_NAME!:!IMAGE_TAG!

    echo.
    echo Logging in to Docker Hub...
    echo !DOCKER_PASSWORD! | docker login --username !DOCKER_USERNAME! --password-stdin
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Docker Hub login failed
        exit /b 1
    )

) else (
    echo ERROR: Invalid choice. Exiting.
    exit /b 1
)

echo.
echo Building Docker image...
echo   Image: !FULL_IMAGE_NAME!
docker build -f Dockerfile -t "!FULL_IMAGE_NAME!" .
if !ERRORLEVEL! neq 0 (
    echo ERROR: Docker build failed
    exit /b 1
)

echo.
echo Pushing Docker image...
docker push "!FULL_IMAGE_NAME!"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Docker push failed
    exit /b 1
)

echo.
echo === Build and push complete ===
echo Image: !FULL_IMAGE_NAME!

endlocal
