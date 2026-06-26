@echo off
rem Build and run. Linking to a native .exe needs the MSVC toolchain, but the
rem shell you build Odin in already has it; nothing to set up here. If link.exe
rem is missing, open an "x64 Native Tools Command Prompt" and run this again.
rem Usage:  run.bat [port]   (default 8080)
setlocal
cd /d "%~dp0"

if not exist "odin-http\" goto :noprep
if not exist "static\htmx.min.js" goto :noprep

if not exist "bin\" mkdir bin
odin build src -out:bin\demo.exe
if errorlevel 1 exit /b 1

set "PORT=%~1"
if "%PORT%"=="" set "PORT=8080"
start "" "http://localhost:%PORT%"
bin\demo.exe %*
exit /b 0

:noprep
echo Dependencies are missing. Run prepare.bat first.
exit /b 1
