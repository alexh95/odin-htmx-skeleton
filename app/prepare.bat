@echo off
rem One-time setup: fetch the two things the build needs that aren't in this repo.
rem   1. odin-http  - the HTTP library, cloned next to the sources.
rem   2. htmx.min.js - embedded into the binary via #load at compile time.
rem Idempotent: re-running skips whatever is already in place.
setlocal
cd /d "%~dp0"

if exist "odin-http\" (
  echo [skip] odin-http already cloned.
) else (
  echo [get ] cloning odin-http ...
  git clone --depth 1 https://github.com/laytan/odin-http odin-http
  if errorlevel 1 goto :fail
)

if exist "static\htmx.min.js" (
  echo [skip] static\htmx.min.js already present.
) else (
  echo [get ] downloading htmx.min.js ...
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing 'https://unpkg.com/htmx.org@2/dist/htmx.min.js' -OutFile 'static\htmx.min.js'"
  if errorlevel 1 goto :fail
)

echo.
echo Ready. Start the server with:  run.bat
exit /b 0

:fail
echo.
echo prepare failed. See the message above.
exit /b 1
