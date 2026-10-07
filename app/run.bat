@echo off
rem Build and run. Linking to a native .exe needs the MSVC + Windows SDK libraries,
rem which Odin finds by itself (and links with its bundled radlink); nothing to set
rem up here. If linking fails, open an "x64 Native Tools Command Prompt" and retry.
rem Usage:  run.bat [port]   (default 8080)
setlocal
cd /d "%~dp0"

if not exist "odin-http\" goto :noprep
if not exist "static\htmx.min.js" goto :noprep
if not exist "vendor\sqlite\sqlite3.lib" goto :noprep

if not exist "bin\" mkdir bin
odin build src -out:bin\demo.exe
if errorlevel 1 exit /b 1

set "PORT=%~1"
if "%PORT%"=="" set "PORT=8080"
rem Local dev persists to .\data.db by default (gitignored); set DB_PATH=:memory:
rem for an ephemeral, freshly-seeded store.
if "%DB_PATH%"=="" set "DB_PATH=data.db"
start "" "http://localhost:%PORT%"
bin\demo.exe %*
exit /b 0

:noprep
echo Dependencies are missing. Run prepare.bat first.
exit /b 1
