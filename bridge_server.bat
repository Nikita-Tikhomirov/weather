@echo off
REM Start the Project Bridge Server for mobile-to-PC terminal control
REM The mobile app connects to this server to launch/manage deepseek-tui sessions
REM 
REM Make sure deepseek-tui is in PATH, and Python 3.10+ is installed
REM Run this on PC startup or manually before using project chats from mobile

cd /d "%~dp0"
echo Starting Project Bridge Server on port 9876...
echo Mobile app should connect to: YOUR_PC_IP:9876
echo.
python project_bridge.py --port 9876 --host 0.0.0.0
pause
