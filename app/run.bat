@echo off
rem Build a profile and run it. Linking to a native .exe needs the MSVC + Windows SDK
rem libraries, which Odin finds by itself (and links with its bundled radlink); nothing
rem to set up here. If linking fails, open an "x64 Native Tools Command Prompt" and retry.
rem Usage:  run.bat [port]   (default 8080; set PROFILE=minimal for another profile,
rem skeleton by default; set OPEN=1 to also open it in the browser)
setlocal
cd /d "%~dp0"

if "%PROFILE%"=="" set "PROFILE=skeleton"
if not exist "vendor\htmx\htmx.min.js" goto :noprep
if not exist "build\%PROFILE%\main.js" goto :noprep

rem A running server holds its exe open, and the linker then fails with a bare
rem "don't have access to write". Appending nothing to the file fails the same
rem way, so try that first and say what is actually wrong.
if exist "bin\%PROFILE%.exe" (
  2>nul ( >>"bin\%PROFILE%.exe" call ) || (
    echo bin\%PROFILE%.exe is in use: a server from an earlier run.bat is probably still running.
    echo Stop it ^(Ctrl+C in its window^) and run this again.
    exit /b 1
  )
)
call ..\build.bat %PROFILE%
if errorlevel 1 exit /b 1

if not "%~1"=="" set "PORT=%~1"
if "%PORT%"=="" set "PORT=8080"
rem A SQLite build persists to .\data.db by default (gitignored), seeded with the demo
rem rows; set DB_PATH=:memory: for an ephemeral, freshly-seeded store. A memory build
rem has neither variable.
bin\%PROFILE%.exe --features --json | findstr /c:"\"store\": \"sqlite\"" >nul
if not errorlevel 1 (
  if "%DB_PATH%"=="" set "DB_PATH=data.db"
  if "%SEED%"=="" set "SEED=1"
)
rem 127.0.0.1, not localhost: the server listens on IPv4 loopback only, and on
rem Windows "localhost" tries ::1 first, which costs ~200 ms per request.
if "%OPEN%"=="1" start "" "http://127.0.0.1:%PORT%"
bin\%PROFILE%.exe
exit /b 0

:noprep
echo Dependencies are missing. Run prepare.bat first.
exit /b 1
