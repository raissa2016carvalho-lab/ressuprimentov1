@echo off
chcp 65001 >nul
cd /d C:\painel-protheus

REM ============================================================================
REM  Inicia TODOS os syncs dos painéis B&Q (cada um abre na sua janela).
REM  Entre um e outro espera 30 segundos, para não carregar o banco do Protheus
REM  com todos ao mesmo tempo (isso travava o login do sistema).
REM  Se algum arquivo .py não estiver na pasta, ele é pulado e avisa no final.
REM ============================================================================

REM usa o "py" (como você roda no CMD); se não tiver, usa o "python"
set PY=python
where py >nul 2>nul && set PY=py
set FALTAM=

REM ── NOTAS FISCAIS / RECEBIMENTO  (notas.html, recebimento.html) ──────────────
REM    NFe Master: fica rodando e revisa a cada 30 minutos (não feche a janela)
call :rodar "sync_nfe_master" "sync_nfe_master.py --loop"
REM    Entradas SD1 (lançamento na SD1 e SLA das notas)
call :rodar "sync_mov_entrada" "sync_movimentos_entrada.py"

REM ── PAINEL PRINCIPAL / RESSUPRIMENTO  (index.html, gerente.html, formulario.html) ─
REM    Pedidos de compra
call :rodar "sync_pedidos" "sync.py"
REM    SC + pedidos v2 (fonte da verdade do acompanhamento)
call :rodar "sync_sc_v2" "sync_sc_pedidos_v2.py"
REM    Itens + centros de custo + consumo 12 meses (formulário do almoxarife)
call :rodar "sync_ressup" "sync_ressuprimento.py"
REM    Estoque SB2 (estoque nas telas, ruptura, fardamento)
call :rodar "sync_estoque" "sync_estoque_sb2.py"
REM    Entregas do almoxarife
call :rodar "sync_entregas" "sync_entregas.py"

REM ── COMPRAS / FARDAMENTO  (compras.html, fardamento.html) ───────────────────
REM    SCs, pedidos e tabelas prontas do Compras (atualiza também o Fardamento)
call :rodar "upload_compras" "upload_compras.py"
REM    Faturamento SF2 (Comparativo do Compras)
call :rodar "sync_faturamento" "sync_faturamento.py"

REM ── FECHAMENTO DE CONSUMO  (fechamento.html) ─────────────────────────────────
REM    Consumo SCP (requisições com status E)
call :rodar "sync_consumo_scp" "sync_consumo_scp.py"
REM    Devoluções TM001
call :rodar "sync_movmult" "sync_movmult.py"
REM    Consumo anual (Posição de estoque)
call :rodar "sync_consumo_anual" "sync_consumo_anual.py"

REM ── ESTOQUE / RUPTURA / INVENTÁRIO  (estoque.html, ruptura.html) ─────────────
REM    Transferências SD2
call :rodar "sync_sd2" "sync_sd2.py"
REM    Movimentos SD3 (comparativo de estoque)
call :rodar "sync_sd3" "sync_sd3.py"

REM ── DESCONTOS DE EPI  (descontos.html, gerente.html) ─────────────────────────
call :rodar "sync_descontos_epi" "sync_descontos_epi.py"

REM ── ABRIR SC  (abrir-sc.html) ────────────────────────────────────────────────
REM    Funcionários SRA (nome e CC pela matrícula)
call :rodar "sync_funcionarios" "sync_funcionarios.py"
REM    Bloqueio de produtos SB1 (aviso de item bloqueado/ativo)
call :rodar "sync_itens_bloqueio" "sync_itens_bloqueio.py"

REM ── VEÍCULOS  (manutencao.html) ──────────────────────────────────────────────
call :rodar "sync_bens" "sync_bens.py"

REM ── DESLIGADOS em 24/11/2026 (nenhuma tela usa o que eles gravavam):
REM    sync_consumo_comp.py (consumo_mensal_comp) e sync_inventario.py (inventario_agg)
REM    sync_sc_pedidos.py (legado): a tabela sc_pedidos virou uma visão da sc_pedidos_v2

REM ── ESTUDO DE CUSTO MÉDIO (fora do dia a dia; rodar à mão quando precisar) ────
REM    É pesado (centenas de milhares de linhas). Tire o REM da linha abaixo só se quiser rodar sempre.
REM call :rodar "sync_kardex_custo" "sync_kardex_custo.py"

echo.
echo Todos os syncs iniciados!
if defined FALTAM echo Atencao: nao achei estes arquivos na pasta C:\painel-protheus:%FALTAM%
echo.
pause
goto :eof

REM ── abre o sync numa janela nova (se o arquivo existir) e espera 30 segundos ──
:rodar
for /f "tokens=1" %%a in (%2) do set ARQ=%%a
if not exist "%ARQ%" (
  echo Pulando %~1: %ARQ% nao esta na pasta.
  set FALTAM=%FALTAM% %ARQ%
  goto :eof
)
echo Iniciando %~1...
start "%~1" %PY% %~2
timeout /t 30 /nobreak >nul
goto :eof
