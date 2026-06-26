@echo off
rem One-time setup for the two things the build needs that aren't tracked inline.
rem   1. odin-http  - the HTTP library, vendored as a pinned git submodule.
rem   2. htmx.min.js - embedded into the binary via #load at compile time.
rem Idempotent: re-running skips whatever is already in place.
setlocal
cd /d "%~dp0"

if exist "odin-http\server.odin" (
  echo [skip] odin-http submodule already checked out.
) else (
  echo [get ] initializing odin-http submodule ...
  git -C "%~dp0.." submodule update --init app/odin-http
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
