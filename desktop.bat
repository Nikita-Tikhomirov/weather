@echo off
setlocal
set "ROOT=%~dp0"
set "FLUTTER_EXE=%ROOT%mobile_app\build\windows\x64\runner\Release\family_todo_mobile.exe"

if exist "%FLUTTER_EXE%" (
  echo [desktop] Starting Flutter Desktop client...
  start "" "%FLUTTER_EXE%"
  exit /b 0
)

echo [desktop] Flutter EXE not found, fallback to legacy CTk client...
python "%ROOT%desktop_app.py"
