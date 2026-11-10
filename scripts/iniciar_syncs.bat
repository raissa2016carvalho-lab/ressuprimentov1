@echo off
cd /d C:\painel-protheus

REM Cada sync abre na sua janela. Entre um e outro espera 30 segundos,
REM para não carregar o banco com todos ao mesmo tempo (isso travava o login do sistema).

REM ── PEDIDOS DE COMPRA ─────────────────────────────────────────────────────
start "sync_pedidos" python sync.py
timeout /t 30 /nobreak >nul

REM ── SC + PEDIDOS v2 (fonte da verdade) ────────────────────────────────────
start "sync_sc_v2" python sync_sc_pedidos_v2.py
timeout /t 30 /nobreak >nul

REM ── SC + PEDIDOS legado ───────────────────────────────────────────────────
start "sync_sc" python sync_sc_pedidos.py
timeout /t 30 /nobreak >nul

REM ── ENTREGAS ALMOXARIFE ───────────────────────────────────────────────────
start "sync_entregas" python sync_entregas.py
timeout /t 30 /nobreak >nul

REM ── ITENS + CC + CONSUMO 12M (formulário) ────────────────────────────────
start "sync_ressup" python sync_ressuprimento.py
timeout /t 30 /nobreak >nul

REM ── VEÍCULOS ──────────────────────────────────────────────────────────────
start "sync_bens" python sync_bens.py
timeout /t 30 /nobreak >nul

REM ── ESTOQUE SB2 ───────────────────────────────────────────────────────────
start "sync_estoque" python sync_estoque_sb2.py
timeout /t 30 /nobreak >nul

REM ── CONSUMO COMPARATIVO ───────────────────────────────────────────────────
start "sync_consumo_comp" python sync_consumo_comp.py
timeout /t 30 /nobreak >nul

REM ── CONSUMO ANUAL ─────────────────────────────────────────────────────────
start "sync_consumo_anual" python sync_consumo_anual.py
timeout /t 30 /nobreak >nul

REM ── ENTRADAS SD1 ──────────────────────────────────────────────────────────
start "sync_mov_entrada" python sync_movimentos_entrada.py
timeout /t 30 /nobreak >nul

REM ── TRANSFERÊNCIAS SD2 ────────────────────────────────────────────────────
start "sync_sd2" python sync_sd2.py
timeout /t 30 /nobreak >nul

REM ── MOVIMENTOS SD3 (comparativo estoque) ──────────────────────────────────
start "sync_sd3" python sync_sd3.py
timeout /t 30 /nobreak >nul

REM ── INVENTÁRIO ────────────────────────────────────────────────────────────
start "sync_inventario" python sync_inventario.py
timeout /t 30 /nobreak >nul

REM ── DEVOLUÇÕES TM001 (fechamento) ─────────────────────────────────────────
start "sync_movmult" python sync_movmult.py
timeout /t 30 /nobreak >nul

REM ── CONSUMO SCP (fechamento) ──────────────────────────────────────────────
start "sync_consumo_scp" python sync_consumo_scp.py
timeout /t 30 /nobreak >nul

REM ── PAINEL DE COMPRAS (SCs, pedidos e tabelas prontas do Compras) ─────────
start "upload_compras" python upload_compras.py
timeout /t 30 /nobreak >nul

REM ── NOVO: NOTAS DO NFE MASTER (revisa a cada 30 minutos) ──────────────────
start "sync_nfe_master" python sync_nfe_master.py --loop
timeout /t 30 /nobreak >nul

REM ── NOVO: FATURAMENTO SF2 (Comparativo do Compras; roda uma vez) ──────────
start "sync_faturamento" python sync_faturamento.py

echo Todos os syncs iniciados!
