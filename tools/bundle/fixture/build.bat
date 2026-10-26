@echo off
rem build.bat PROFILE [odin flags...]: the one place each profile's four family flags live (PLAN section 7.2).
rem Fixture for spike S0.10, standing in for the repo root's build.bat until M1 writes it.
rem   CMD   the odin command: build (the default), check, run or test
rem   OUT   the binary (default bin\PROFILE.exe)
rem No angle brackets or pipes in these remarks: cmd parses redirections even here.
setlocal
cd /d "%~dp0"
set "P=%~1"
if "%P%"=="" (echo usage: build.bat ^<profile^> [odin flags...] 1>&2 & exit /b 2)
set "FAM="
if "%P%"=="minimal" set "FAM=memory anonymous vanilla lite"
if "%P%"=="streams" set "FAM=memory nick vanilla lite"
if "%P%"=="full" set "FAM=sqlite accounts hyperscript full"
if "%P%"=="lab" set "FAM=memory anonymous hyperscript full"
if "%FAM%"=="" (echo build.bat: unknown profile '%P%' 1>&2 & exit /b 2)
for /f "tokens=1-4" %%a in ("%FAM%") do (
  set "STORE=%%a"
  set "IDENTITY=%%b"
  set "CLIENT=%%c"
  set "THEME=%%d"
)
rem Everything after the profile, verbatim: positional arguments would split -define:K=V at the '='.
set "ARGS=%*"
call set "REST=%%ARGS:*%P%=%%"
if "%CMD%"=="" set "CMD=build"
if "%OUT%"=="" set "OUT=bin\%P%.exe"
odin %CMD% app\cmd\%P% -collection:store=app\stores\%STORE% -collection:identity=app\identity\%IDENTITY% -collection:client=app\platform\client\%CLIENT% -collection:theme=app\platform\theme\%THEME% "-out:%OUT%" %REST%
