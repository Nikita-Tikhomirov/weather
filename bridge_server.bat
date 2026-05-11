@echo off
REM Project Bridge Server — tunnel mode (connects PC to VPS relay)
REM 
REM The VPS (31.129.97.211) runs tunnel_server.py on port 9877.
REM This script connects the PC to the VPS relay.
REM Mobile app connects to VPS, VPS pairs them with this PC.
REM
REM Run this on PC startup. Deepseek-tui must be in PATH.

cd /d "%~dp0"
echo Connecting to VPS tunnel at 31.129.97.211:9877...
echo Mobile app connects to: 31.129.97.211:9877 (fixed, works anywhere)
echo.
python project_bridge.py --tunnel 31.129.97.211:9877
pause
