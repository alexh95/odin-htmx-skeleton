@echo off
rem One-time setup for the two things the build needs that aren't tracked inline.
rem   1. htmx        - htmx.min.js and its extensions (vendor\htmx\PINS), bundled per profile.
rem   2. SQLite      - the pinned amalgamation, compiled to a static lib.
rem odin-http is vendored in-tree (vendor\odin-http, see its UPSTREAM.md): nothing to fetch.
rem Idempotent: re-running skips whatever is already in place.
setlocal
cd /d "%~dp0"

rem odin's -out: writes into bin\ but won't create it; a fresh clone has no bin\.
if not exist "bin\" mkdir bin

rem htmx with its extensions, and _hyperscript, each file pinned exactly (version + SHA-256) for
rem reproducible builds. The digests live in vendor\PACKAGE\PINS, which prepare.sh reads too; a
rem file already present with its digest is kept.
set "HTMX_VERSION=4.0.0"
set "HYPERSCRIPT_VERSION=0.9.94"
call :fetch_pinned htmx htmx.org@%HTMX_VERSION% || goto :fail
call :fetch_pinned hyperscript hyperscript.org@%HYPERSCRIPT_VERSION% || goto :fail

rem --- SQLite amalgamation (pinned; fetched + compiled, mirroring the htmx fetch) ---
rem NO_SQLITE=1 skips it: a memory profile's build needs no SQLite (D18), and CI builds
rem minimal that way, with no library present, to prove it.
if "%NO_SQLITE%"=="1" (
  echo [skip] SQLite: NO_SQLITE=1
  goto :ready
)
set "SQLITE_URL=https://sqlite.org/2026/sqlite-amalgamation-3530400.zip"
set "SQLITE_SHA256=1e71ddf93849c6a6ecf58b827c0692073d2dd7ee40196158068f7b29f422e87d"
set "SQLITE_DIR=vendor\sqlite"

if not exist "%SQLITE_DIR%" mkdir "%SQLITE_DIR%"

rem Ensure the pinned, verified source is present (skips when the stamp matches).
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $d='%SQLITE_DIR%'; $w='%SQLITE_SHA256%'; if((Test-Path \"$d\sqlite3.c\") -and (Test-Path \"$d\sqlite3.h\") -and ((Get-Content \"$d\.stamp\" -EA SilentlyContinue) -eq $w)){Write-Host '[skip] SQLite amalgamation already present.';exit 0}; Write-Host '[get ] downloading sqlite amalgamation ...'; $z=Join-Path $env:TEMP 'sqlite-amalg.zip'; Invoke-WebRequest -UseBasicParsing '%SQLITE_URL%' -OutFile $z; $g=(Get-FileHash $z -Algorithm SHA256).Hash.ToLower(); if($g -ne $w){Write-Error \"SQLite checksum mismatch: expected $w got $g\";exit 1}; $x=Join-Path $env:TEMP 'sqlite-amalg'; if(Test-Path $x){Remove-Item $x -Recurse -Force}; Expand-Archive $z $x -Force; Copy-Item (Get-ChildItem $x -Recurse -Include sqlite3.c,sqlite3.h).FullName $d -Force; Set-Content \"$d\.stamp\" $w"
if errorlevel 1 goto :fail

rem D16's flags (PLAN 11.2; spike S0.11), the same string as prepare.sh's. .flags records what
rem the lib was built with, so a flag change rebuilds it: a lib newer than its source isn't enough.
set "SQLITE_FLAGS=-DSQLITE_DQS=0 -DSQLITE_DEFAULT_FOREIGN_KEYS=1 -DSQLITE_THREADSAFE=2 -DSQLITE_DEFAULT_MEMSTATUS=0 -DSQLITE_OMIT_LOAD_EXTENSION -DSQLITE_OMIT_SHARED_CACHE -DSQLITE_ENABLE_FTS5"

rem Compile to sqlite3.lib once (skip if the lib is newer than the source and built with these flags).
powershell -NoProfile -Command "$d='%SQLITE_DIR%'; if((Test-Path \"$d\sqlite3.lib\") -and ((Get-Item \"$d\sqlite3.lib\").LastWriteTime -ge (Get-Item \"$d\sqlite3.c\").LastWriteTime) -and ((Get-Content \"$d\.flags\" -EA SilentlyContinue) -eq '%SQLITE_FLAGS%')){exit 0}else{exit 1}"
if not errorlevel 1 (
  echo [skip] sqlite3.lib is up to date.
  goto :ready
)

rem Only compiling needs a C compiler, so it is looked for here, not up front: a re-run from a
rem plain shell, with the lib already built, has nothing to compile. MSVC's cl first; else clang
rem with llvm-lib, which S0.11 checked builds a lib Odin links.
pushd "%SQLITE_DIR%"
if exist sqlite3.lib del /q sqlite3.lib
where cl >nul 2>nul
if not errorlevel 1 (
  echo [cc  ] compiling sqlite3.c with cl ...
  rem /MT ^(static CRT^) to match how Odin links the CRT on Windows; /MD's dynamic
  rem imports ^(__imp_*^) don't resolve against Odin's static libucrt.lib.
  cl /nologo /c /O2 /MT %SQLITE_FLAGS% sqlite3.c || (popd & goto :fail)
  lib /nologo /OUT:sqlite3.lib sqlite3.obj || (popd & goto :fail)
  goto :compiled
)
where clang >nul 2>nul
if errorlevel 1 goto :nocc
where llvm-lib >nul 2>nul
if errorlevel 1 goto :nocc
echo [cc  ] compiling sqlite3.c with clang ...
clang -O2 -fms-runtime-lib=static %SQLITE_FLAGS% -c sqlite3.c -o sqlite3.obj || (popd & goto :fail)
llvm-lib -nologo -out:sqlite3.lib sqlite3.obj || (popd & goto :fail)
:compiled
del /q sqlite3.obj
>.flags echo %SQLITE_FLAGS%
popd
goto :ready

:nocc
popd
echo.
echo error: neither MSVC's cl.exe nor clang with llvm-lib is on PATH, and sqlite3.lib needs
echo building. Install the Build Tools ^(not full VS^):
echo   1^) winget install --id Microsoft.VisualStudio.2022.BuildTools -e
echo   2^) in the installer pick the "Desktop development with C++" workload
echo      ^(minimally MSVC v143 toolset + Windows 11 SDK^)
echo   3^) run this from an "x64 Native Tools Command Prompt for VS 2022"
goto :fail

:ready
rem Each profile's assets (tools/bundle, PLAN 12.1): its htmx bundle, its stylesheet and its
rem client's app.js, with a .br and a .gz beside each, in build\PROFILE\, where build.bat's
rem BUILD_DIR embeds them from. Cheap, so it runs every time: an edited asset is picked up.
rem Without brotli or gzip (Git for Windows ships both) a dev build ships fewer encodings.
echo [bndl] building the profiles' assets ...
pushd ..
odin build tools/bundle -out:app/bin/bundle.exe -o:minimal >nul || (popd & goto :fail)
rem Every profile this checkout has.
for /d %%d in (app\cmd\*) do (
  if exist "%%d\main.odin" (
    app\bin\bundle.exe %%~nxd >nul || (popd & goto :fail)
  )
)
popd
echo.
echo Ready. Build a profile from the repo root:  build.bat skeleton
exit /b 0

:fail
echo.
echo prepare failed. See the message above.
exit /b 1

rem fetch_pinned DIR PACKAGE@VERSION: every file vendor\DIR\PINS names, from unpkg's dist/.
:fetch_pinned
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $n=0; foreach($l in Get-Content 'vendor\%~1\PINS'){ if($l -match '^\s*(#|$)'){continue}; $p=$l -split '\s+'; $f=Join-Path 'vendor\%~1' $p[0]; New-Item -ItemType Directory -Force (Split-Path $f) | Out-Null; $w=$p[1]; if((Test-Path $f) -and ((Get-FileHash $f -Algorithm SHA256).Hash.ToLower() -eq $w)){continue}; Write-Host ('[get ] %~2 '+$p[0]+' ...'); Invoke-WebRequest -UseBasicParsing ('https://unpkg.com/%~2/dist/'+$p[0]) -OutFile $f; $g=(Get-FileHash $f -Algorithm SHA256).Hash.ToLower(); if($g -ne $w){Remove-Item $f -Force; Write-Error ('%~2 '+$p[0]+' checksum mismatch: expected '+$w+' got '+$g); exit 1}; $n++ }; if($n -eq 0){Write-Host '[skip] %~2 already present.'}"
exit /b %errorlevel%
