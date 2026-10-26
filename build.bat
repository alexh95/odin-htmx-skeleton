@echo off
rem build.bat PROFILE [odin flags...]: the one place a profile's family flags live (PLAN 7.2).
rem   set CMD=build (default) ^| check ^| test ^| run
rem   set VERSION=TAG becomes -define:VERSION (default dev), sent as x-version.
rem Every path here is relative to the repo root; the binary lands in app\bin\PROFILE.exe.
rem (No angle brackets in these comments: cmd still parses redirections on a rem line.)
rem The same table as build.sh: change both together.
setlocal
cd /d "%~dp0"

set "P=%~1"
if "%P%"=="" (
  echo usage: build.bat ^<minimal^|skeleton^> [odin flags...] 1>&2
  exit /b 2
)
set "SRC=%P%"
if "%P%"=="minimal" (
  set "STORE=memory" & set "ID=platform/authz/anonymous" & set "CLIENT=vanilla" & set "THEME=lite"
) else if "%P%"=="skeleton" (
  set "STORE=sqlite" & set "ID=platform/authz/anonymous" & set "CLIENT=vanilla" & set "THEME=full"
) else (
  echo build.bat: unknown profile '%P%' ^(minimal, skeleton^) 1>&2
  exit /b 2
)

rem The odin flags after the profile, cut from %* rather than collected with shift: cmd splits
rem arguments on '=', which would break -define:NAME=value.
set "REST=%*"
call set "REST=%%REST:*%P%=%%"

if "%CMD%"=="" set "CMD=build"
set "OUT="
if "%CMD%"=="build" set "OUT=-out:app/bin/%P%.exe"
if "%CMD%"=="run" set "OUT=-out:app/bin/%P%.exe"
if "%CMD%"=="test" set "OUT=-out:app/bin/%P%-test.exe"
if not "%CMD%"=="build" if not "%CMD%"=="run" if not "%CMD%"=="test" if not "%CMD%"=="check" (
  echo build.bat: unknown CMD '%CMD%' ^(build, check, test, run^) 1>&2
  exit /b 2
)
if "%VERSION%"=="" set "VERSION=dev"
if not exist "app\bin\" mkdir app\bin

odin %CMD% app/cmd/%SRC% %OUT% -collection:store=app/stores/%STORE% -collection:identity=app/%ID% -collection:client=app/platform/client/%CLIENT% -collection:theme=app/platform/theme/%THEME% -define:VERSION=%VERSION% -vet -strict-style -warnings-as-errors%REST%
exit /b %errorlevel%
