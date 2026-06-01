@echo off
title Inventario - servidor local
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0servidor.ps1"
pause
