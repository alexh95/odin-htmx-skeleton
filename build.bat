@echo off
rem build.bat PROFILE [odin flags...]: the one place a profile's family flags live (PLAN 7.2).
rem   set CMD=build (default) ^| check ^| test ^| run
rem   set VERSION=TAG becomes -define:VERSION (default dev), sent as x-version.
rem   set OUT=PATH builds there instead (tools/bundle's scan build, beside a running binary).
rem Every path here is relative to the repo root; the binary lands in app\bin\PROFILE.exe, and
rem the assets prepare built for the profile (app\build\PROFILE\) are embedded from BUILD_DIR.
rem (No angle brackets in these comments: cmd still parses redirections on a rem line.)
rem The same table as build.sh: change both together.
setlocal
cd /d "%~dp0"

set "P=%~1"
if "%P%"=="" (
  echo usage: build.bat ^<minimal^|skeleton^|lab^|streams^> [odin flags...] 1>&2
  exit /b 2
)
set "SRC=%P%"
if "%P%"=="minimal" (
  set "STORE=memory" & set "ID=platform/authz/anonymous" & set "CLIENT=vanilla" & set "THEME=lite"
) else if "%P%"=="skeleton" (
  set "STORE=sqlite" & set "ID=platform/authz/anonymous" & set "CLIENT=vanilla" & set "THEME=full"
) else if "%P%"=="lab" (
  set "STORE=memory" & set "ID=platform/authz/anonymous" & set "CLIENT=hyperscript" & set "THEME=full"
) else if "%P%"=="streams" (
  set "STORE=memory" & set "ID=features/accounts/identity_nick" & set "CLIENT=vanilla" & set "THEME=lite"
) else (
  echo build.bat: unknown profile '%P%' ^(minimal, skeleton, lab, streams^) 1>&2
  exit /b 2
)

rem The odin flags after the profile, cut from %* rather than collected with shift: cmd splits
rem arguments on '=', which would break -define:NAME=value.
set "REST=%*"
call set "REST=%%REST:*%P%=%%"

if "%CMD%"=="" set "CMD=build"
if not "%CMD%"=="build" if not "%CMD%"=="run" if not "%CMD%"=="test" if not "%CMD%"=="check" (
  echo build.bat: unknown CMD '%CMD%' ^(build, check, test, run^) 1>&2
  exit /b 2
)
set "BIN=app/bin/%P%.exe"
if "%CMD%"=="test" set "BIN=app/bin/%P%-test.exe"
if not "%OUT%"=="" set "BIN=%OUT%"
set "OUTFLAG="
if not "%CMD%"=="check" set "OUTFLAG=-out:%BIN%"
if "%CMD%"=="test" set "OUTFLAG=-out:%BIN% -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true"
if "%VERSION%"=="" set "VERSION=dev"
rem Odin reads a define of digits alone as an integer: name a commit sha-<7>, as the image tags do.
echo %VERSION%| findstr /r "^[0-9][0-9]*$" >nul && (echo build.bat: VERSION=%VERSION% is all digits, which Odin reads as a number: use sha-%VERSION% 1>&2 & exit /b 2)
if not exist "app\bin\" mkdir app\bin

odin %CMD% app/cmd/%SRC% %OUTFLAG% -collection:store=app/stores/%STORE% -collection:identity=app/%ID% -collection:client=app/platform/client/%CLIENT% -collection:theme=app/platform/theme/%THEME% -define:VERSION=%VERSION% -define:BUILD_DIR=../../build/%P% -vet -vet-cast -vet-semicolon -vet-tabs -vet-using-param -disallow-do -strict-style -warnings-as-errors%REST%
exit /b %errorlevel%
