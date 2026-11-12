@echo off
setlocal
if "%~1"=="" (
  echo Arraste um MP4 para este arquivo para converter video e audio.
  echo A conversao permanece no computador. Nada sera enviado automaticamente.
  pause
  exit /b 1
)
set "VIDEO_PYTHON=%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
if not exist "%VIDEO_PYTHON%" set "VIDEO_PYTHON=python"
"%VIDEO_PYTHON%" "%~dp0tools\add_video.py" "%~f1"
set "VIDEO_RESULT=%ERRORLEVEL%"
if not "%VIDEO_RESULT%"=="0" echo Confira a mensagem acima. A conversao anterior foi preservada.
pause
exit /b %VIDEO_RESULT%
