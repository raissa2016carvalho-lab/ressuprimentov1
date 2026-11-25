@echo off
chcp 65001 >nul
title Maestro dos syncs - BeQ - nao feche esta janela
cd /d C:\painel-protheus

REM ============================================================================
REM  Abre o MAESTRO (rodar_syncs.py): uma janela so, que roda todos os syncs
REM  um de cada vez, nos horarios da tabela que fica no comeco do rodar_syncs.py.
REM  Ao abrir, roda todos uma vez. Depois segue os horarios.
REM  O log de cada dia fica em C:\painel-protheus\logs
REM  (O jeito antigo, uma janela por sync, esta no iniciar_syncs_antigo.bat)
REM ============================================================================

set PY=python
where py >nul 2>nul && set PY=py

if not exist "rodar_syncs.py" (
  echo Nao achei o rodar_syncs.py na pasta C:\painel-protheus.
  pause
  goto :eof
)
%PY% rodar_syncs.py
echo.
echo O maestro parou. Feche esta janela e abra o iniciar_syncs.bat de novo.
pause
