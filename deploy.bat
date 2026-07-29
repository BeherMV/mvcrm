@echo off
setlocal
cd /d "%~dp0"

echo === Alteracoes detectadas ===
git status --short
echo.

git add -A
git diff --cached --quiet
if %errorlevel%==0 (
  echo Nada para commitar. Nada foi enviado.
  timeout /t 4 >nul
  exit /b 0
)

for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format 'yyyy-MM-dd HH:mm'"') do set TS=%%i

git commit -m "update %TS%"
if errorlevel 1 goto :err

git push
if errorlevel 1 goto :err

echo.
echo === Push enviado. Vercel builda em ~30s. ===
timeout /t 5 >nul
exit /b 0

:err
echo.
echo === ERRO. Veja a mensagem acima. ===
pause
exit /b 1
