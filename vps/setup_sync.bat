@echo off
title 9algo sync - setup
REM ================================================================
REM 9algo VPS <-> GitHub sync. Dobel klik sekali; setelah itu jalan otomatis tiap login VPS.
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

REM --- konfigurasi (sekali)
if not exist sync_config.json (
  echo.
  echo Isi 3 data berikut ^(lihat petunjuk dari Claude^):
  set /p GHOWNER=  1. Username GitHub kamu         : 
  set /p GHREPO=  2. Nama repo ^(mis. 9algo-vps^)    : 
  set /p GHTOKEN=  3. Token GitHub ^(github_pat_...^): 
)
if not exist sync_config.json (
  "%PY%" -c "import json,sys; json.dump({'owner':sys.argv[1].strip(),'repo':sys.argv[2].strip(),'token':sys.argv[3].strip(),'interval':90,'allow_deploy':True}, open('sync_config.json','w'), indent=1)" "%GHOWNER%" "%GHREPO%" "%GHTOKEN%"
)

REM --- jalan otomatis tiap login (Task Scheduler)
schtasks /create /f /sc onlogon /tn "9algo_sync" /tr "\"%PY%\" \"%~dp09algo_sync.py\"" >nul 2>nul
if errorlevel 1 (echo [i] Gagal daftar Task Scheduler - sync tetap jalan sekarang, tapi setelah VPS restart jalankan setup_sync.bat lagi.) else (echo [OK] Sync otomatis jalan tiap login VPS.)

REM --- jalan sekarang di jendela ini
echo.
echo Sync berjalan. Jendela ini boleh di-minimize, JANGAN ditutup.
echo Ganti token/repo: hapus sync_config.json lalu jalankan file ini lagi.
echo.
"%PY%" "%~dp09algo_sync.py"
pause
