@echo off
cd /d "%~dp0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0publish-nvidia-driver.ps1" %*

set "EXIT_CODE=%ERRORLEVEL%"

echo.

if not "%EXIT_CODE%"=="0" (
    echo Publishing failed with exit code %EXIT_CODE%.
) else (
    echo Publishing completed successfully.
)

pause
exit /b %EXIT_CODE%
