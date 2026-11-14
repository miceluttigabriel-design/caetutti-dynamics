@echo off
echo Iniciando Caetutti Dynamics...
start "Caetutti Backend" cmd /k "%~dp0start-backend.bat"
timeout /t 5 /nobreak >nul
start "Caetutti Frontend" cmd /k "%~dp0start-frontend.bat"
echo.
echo Backend:  http://localhost:4000
echo Frontend: http://localhost:3000
echo Admin:    http://localhost:3000/admin
echo.
pause
