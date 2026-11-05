@echo off
title 9algo sync - setup
REM ================================================================
REM 9algo VPS <-> GitHub sync (+ backtest otomatis). Dobel klik; setelah itu jalan otomatis tiap login VPS.
REM ================================================================
cd /d "%~dp0"
set TLS=[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;

REM --- Python (pakai yang sudah ada / pasang otomatis)
set PY=
for %%p in ("%LOCALAPPDATA%\Programs\Python\Python312\python.exe" "%ProgramFiles%\Python312\python.exe") do if exist %%p if not defined PY set PY=%%~p
if not defined PY for /f "delims=" %%p in ('where python 2^>nul ^| findstr /v /i "WindowsApps"') do if not defined PY set PY=%%p
if not defined PY (
  echo Memasang Python 3.12...
  powershell -NoProfile -Command "%TLS% Invoke-WebRequest -UseBasicParsing -Uri https://www.python.org/ftp/python/3.12.8/python-3.12.8-amd64.exe -OutFile python-setup.exe"
  python-setup.exe /quiet InstallAllUsers=0 PrependPath=1 Include_pip=1 Include_test=0 Include_launcher=0
  del python-setup.exe
  set PY=%LOCALAPPDATA%\Programs\Python\Python312\python.exe
)
if not exist "%PY%" (
  echo [!] Python tidak ditemukan. Kirim screenshot jendela ini ke Claude.
  pause
  exit /b 1
)

REM --- matikan sync lama kalau masih jalan (supaya tidak dobel)
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='python.exe'\" | Where-Object { $_.CommandLine -like '*9algo_sync.py*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }" >nul 2>nul

REM --- konfigurasi (hanya menanyakan yang belum ada)
"%PY%" "%~dp0setup_config.py"

REM --- jalan otomatis tiap login (Task Scheduler)
schtasks /create /f /sc onlogon /tn "9algo_sync" /tr "\"%PY%\" \"%~dp09algo_sync.py\"" >nul 2>nul
if errorlevel 1 (echo [i] Gagal daftar Task Scheduler - setelah VPS restart jalankan setup_sync.bat lagi.) else (echo [OK] Sync otomatis jalan tiap login VPS.)

echo.
echo Sync berjalan. Jendela ini boleh di-minimize, JANGAN ditutup.
echo.
"%PY%" "%~dp09algo_sync.py"
pause
