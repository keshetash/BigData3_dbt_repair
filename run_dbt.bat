@echo off
cd /d %~dp0
call .venv\Scripts\activate.bat
dbt run --profiles-dir .
echo.
echo === DBT run completed at %date% %time% ===
