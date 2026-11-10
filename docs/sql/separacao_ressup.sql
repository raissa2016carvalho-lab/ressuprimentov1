-- Separação do ressuprimento: status da separação em cada solicitação (botão "Concluir separação")
alter table public.solicitacoes
  add column if not exists sep_status text,            -- pendente / em_separacao / concluida
  add column if not exists sep_operador text,
  add column if not exists sep_concluida_em timestamptz;

-- As 43 solicitações em aberto hoje (10/11) já foram separadas: marcar como concluídas
update public.solicitacoes
set sep_status = 'concluida', sep_operador = 'carga inicial 10/11', sep_concluida_em = now()
where status in ('pendente','aguardando_master');

-- DESFAZER:
-- alter table public.solicitacoes drop column sep_status, drop column sep_operador, drop column sep_concluida_em;
