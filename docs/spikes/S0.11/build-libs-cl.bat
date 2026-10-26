@echo off
rem S0.11: compile the pinned SQLite amalgamation with MSVC cl, the way
rem prepare.bat does today (/O2 /MT), with the default and the tuned flags.
rem   build-libs-cl.bat <dir with sqlite3.c> <out dir>
rem Writes <out>\{cl_default,cl_tuned,cl_tuned_dash}\sqlite3.lib and build.txt.
rem cl_tuned_dash passes the same flags as -D...: cl takes them, so one flag
rem string can serve cl and clang.
rem Needs cl and lib on PATH: run it from an "x64 Native Tools" prompt, or set
rem VCVARS to vcvars64.bat and this calls it first.
setlocal
set "SRC=%~f1"
set "OUT=%~f2"
if not "%VCVARS%"=="" call "%VCVARS%" >nul
where cl >nul 2>nul || (echo cl not on PATH & exit /b 1)
set "TUNED=/DSQLITE_DQS=0 /DSQLITE_DEFAULT_FOREIGN_KEYS=1 /DSQLITE_THREADSAFE=2 /DSQLITE_DEFAULT_MEMSTATUS=0 /DSQLITE_OMIT_LOAD_EXTENSION /DSQLITE_OMIT_SHARED_CACHE /DSQLITE_ENABLE_FTS5"
set "TUNED_DASH=-DSQLITE_DQS=0 -DSQLITE_DEFAULT_FOREIGN_KEYS=1 -DSQLITE_THREADSAFE=2 -DSQLITE_DEFAULT_MEMSTATUS=0 -DSQLITE_OMIT_LOAD_EXTENSION -DSQLITE_OMIT_SHARED_CACHE -DSQLITE_ENABLE_FTS5"
call :one cl_default ""
if errorlevel 1 exit /b 1
call :one cl_tuned "%TUNED%"
if errorlevel 1 exit /b 1
call :one cl_tuned_dash "%TUNED_DASH%"
if errorlevel 1 exit /b 1
exit /b 0

:one
set "D=%OUT%\%~1"
if not exist "%D%" mkdir "%D%"
pushd "%D%"
cl /nologo /c /O2 /MT %~2 "%SRC%\sqlite3.c" /Fosqlite3.obj || (popd & exit /b 1)
lib /nologo /OUT:sqlite3.lib sqlite3.obj || (popd & exit /b 1)
del /q sqlite3.obj
echo %~1 cl /O2 /MT %~2> build.txt
popd
exit /b 0
