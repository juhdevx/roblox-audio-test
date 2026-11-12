@echo off
setlocal
set "MEDIA_WORKBENCH_PYTHON=%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
if not exist "%MEDIA_WORKBENCH_PYTHON%" set "MEDIA_WORKBENCH_PYTHON=python"
"%MEDIA_WORKBENCH_PYTHON%" "%~dp0tools\media_workbench.py"
if errorlevel 1 pause
