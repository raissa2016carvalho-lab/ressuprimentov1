# Syncs Python (C:\painel-protheus)

- Leem o banco do Protheus e gravam no Supabase com a chave `service_role` (ignora RLS).
- Cada script roda uma vez e fica em loop esperando o horário (`schedule` + `while True`).
- Muitos fazem **apagar a tabela (truncate) e regravar tudo**. Se parar no meio, a tabela fica incompleta
  até rodar de novo.
- **Problema de 22/10**: 18 processos Python rodando ao mesmo tempo sobrecarregaram o banco
  (timeouts no site e nos syncs). Solução: `taskkill /f /im python.exe` e rodar **um por vez**.

## Ordem sugerida (menor → maior), um por vez
```
cd /d C:\painel-protheus && python sync_bens.py
... sync_consumo_anual, sync_inventario, sync_estoque_sb2, sync_entregas, sync_consumo_comp,
sync_sd2, sync_sd3, sync_movmult, sync_sc_pedidos, sync_sc_pedidos_v2, upload_compras,
sync_movimentos_entrada, sync_ressuprimento, sync_consumo_scp
```

## Ideias combinadas (não feitas)
- `rodar_uma_vez.py` + `fila_syncs.bat` + Agendador de Tarefas do Windows (fila em horários fixos).
- Syncs que **não alimentam o site** (confirmar se são usados fora, ex. Power BI):
  `sync_inventario` (inventario_*), `sync_entregas` (entregas_almoxarife), `sync_consumo_comp`
  (consumo_mensal_comp), `sync_sd2` (movimentos_saida?), `sync_bens` (bens deste projeto; a manutenção usa outro).
- Gravar só o que mudou em vez de apagar e regravar.
