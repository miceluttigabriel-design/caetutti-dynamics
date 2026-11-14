@echo off
cd /d "%~dp0frontend"
set NEXT_PUBLIC_API_URL=http://localhost:4000
npx next dev -p 3000
pause
