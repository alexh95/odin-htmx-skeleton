@echo off
rem One-time setup for the two things the build needs that aren't tracked inline.
rem   1. odin-http  - the HTTP library, vendored as a pinned git submodule.
rem   2. htmx.min.js - embedded into the binary via #load at compile time.
rem Idempotent: re-running skips whatever is already in place.
setlocal
cd /d "%~dp0"

rem odin's -out: writes into bin\ but won't create it; a fresh clone has no bin\.
if not exist "bin\" mkdir bin

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

rem --- SQLite amalgamation (pinned; fetched + compiled, mirroring the htmx fetch) ---
set "SQLITE_URL=https://sqlite.org/2026/sqlite-amalgamation-3530300.zip"
set "SQLITE_SHA256=646421e12aac110282ef8cc68f1a62d4bb15fc7b8f09da0b53e29ee690500431"
set "SQLITE_DIR=vendor\sqlite"

rem Compiling the amalgamation needs MSVC's cl.exe (same env Odin's linker needs).
where cl >nul 2>nul
if errorlevel 1 (
  echo.
  echo error: MSVC cl.exe not found on PATH. Install the Build Tools ^(not full VS^):
  echo   1^) winget install --id Microsoft.VisualStudio.2022.BuildTools -e
  echo   2^) in the installer pick the "Desktop development with C++" workload
  echo      ^(minimally MSVC v143 toolset + Windows 11 SDK^)
  echo   3^) run this from an "x64 Native Tools Command Prompt for VS 2022"
  goto :fail
)
if not exist "%SQLITE_DIR%" mkdir "%SQLITE_DIR%"

rem Ensure the pinned, verified source is present (skips when the stamp matches).
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $d='%SQLITE_DIR%'; $w='%SQLITE_SHA256%'; if((Test-Path \"$d\sqlite3.c\") -and (Test-Path \"$d\sqlite3.h\") -and ((Get-Content \"$d\.stamp\" -EA SilentlyContinue) -eq $w)){Write-Host '[skip] SQLite amalgamation already present.';exit 0}; Write-Host '[get ] downloading sqlite amalgamation ...'; $z=Join-Path $env:TEMP 'sqlite-amalg.zip'; Invoke-WebRequest -UseBasicParsing '%SQLITE_URL%' -OutFile $z; $g=(Get-FileHash $z -Algorithm SHA256).Hash.ToLower(); if($g -ne $w){Write-Error \"SQLite checksum mismatch: expected $w got $g\";exit 1}; $x=Join-Path $env:TEMP 'sqlite-amalg'; if(Test-Path $x){Remove-Item $x -Recurse -Force}; Expand-Archive $z $x -Force; Copy-Item (Get-ChildItem $x -Recurse -Include sqlite3.c,sqlite3.h).FullName $d -Force; Set-Content \"$d\.stamp\" $w"
if errorlevel 1 goto :fail

rem Compile to sqlite3.lib once (skip if the lib is newer than the source).
powershell -NoProfile -Command "if((Test-Path '%SQLITE_DIR%\sqlite3.lib') -and ((Get-Item '%SQLITE_DIR%\sqlite3.lib').LastWriteTime -ge (Get-Item '%SQLITE_DIR%\sqlite3.c').LastWriteTime)){exit 0}else{exit 1}"
if not errorlevel 1 (
  echo [skip] sqlite3.lib is up to date.
) else (
  echo [cc  ] compiling sqlite3.c with cl ...
  pushd "%SQLITE_DIR%"
  rem /MT (static CRT) to match how Odin links the CRT on Windows; /MD's dynamic
  rem imports (__imp_*) don't resolve against Odin's static libucrt.lib.
  cl /nologo /c /O2 /MT sqlite3.c || ( popd ^& goto :fail )
  lib /nologo /OUT:sqlite3.lib sqlite3.obj || ( popd ^& goto :fail )
  del /q sqlite3.obj
  popd
)

echo.
echo Ready. Start the server with:  run.bat
exit /b 0

:fail
echo.
echo prepare failed. See the message above.
exit /b 1
