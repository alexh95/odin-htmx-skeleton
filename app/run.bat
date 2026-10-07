@echo off
rem Build and run. Linking to a native .exe needs the MSVC + Windows SDK libraries,
rem which Odin finds by itself (and links with its bundled radlink); nothing to set
rem up here. If linking fails, open an "x64 Native Tools Command Prompt" and retry.
rem Usage:  run.bat [port]   (default 8080; set OPEN=1 to also open it in the browser)
setlocal
cd /d "%~dp0"

if not exist "odin-http\" goto :noprep
if not exist "static\htmx.min.js" goto :noprep
if not exist "vendor\sqlite\sqlite3.lib" goto :noprep

if not exist "bin\" mkdir bin
rem A running server holds its exe open, and the linker then fails with a bare
rem "don't have access to write". Appending nothing to the file fails the same
rem way, so try that first and say what is actually wrong.
if exist "bin\demo.exe" (
  2>nul ( >>"bin\demo.exe" call ) || (
    echo bin\demo.exe is in use: a server from an earlier run.bat is probably still running.
    echo Stop it ^(Ctrl+C in its window^) and run this again.
    exit /b 1
  )
)
odin build src -out:bin\demo.exe
if errorlevel 1 exit /b 1

set "PORT=%~1"
if "%PORT%"=="" set "PORT=8080"
rem Local dev persists to .\data.db by default (gitignored); set DB_PATH=:memory:
rem for an ephemeral, freshly-seeded store.
if "%DB_PATH%"=="" set "DB_PATH=data.db"
rem A file DB is only seeded when asked; a dev store wants the demo rows.
if "%SEED%"=="" set "SEED=1"
rem 127.0.0.1, not localhost: the server listens on IPv4 loopback only, and on
rem Windows "localhost" tries ::1 first, which costs ~200 ms per request.
if "%OPEN%"=="1" start "" "http://127.0.0.1:%PORT%"
bin\demo.exe %*
exit /b 0

:noprep
echo Dependencies are missing. Run prepare.bat first.
exit /b 1
