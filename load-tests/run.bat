@echo off
REM Windows entry point. The driver is one POSIX script (run.sh) so there's a
REM single source of truth; on Windows it runs under Git Bash's `sh`, which ships
REM with Git for Windows. k6 is the real prerequisite either way.
REM Usage mirrors run.sh:  run.bat --quick   |   run.bat --sweep static api
sh "%~dp0run.sh" %*
