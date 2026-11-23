-- 23/11/2026: índices para a exportação do fechamento (pagina consumo_scp por chave, filtrando cc + mês)
create index if not exists idx_consumo_scp_chave on public.consumo_scp (chave);
create index if not exists idx_consumo_scp_cc_mes on public.consumo_scp (cc, mes text_pattern_ops);
