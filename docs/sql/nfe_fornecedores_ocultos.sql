-- Fornecedores ocultos do painel de notas (aplicado em 19/11/2026): PJs da B&Q (pessoas contratadas como PJ).
-- As notas desses CNPJs não aparecem para nenhum usuário do painel, nem pela API. Só a chave de serviço (syncs) e o
-- Supabase (SQL Editor) enxergam. A LISTA de CNPJs fica só no banco (dados pessoais); não versionar aqui.
--
-- Ocultar mais um:   insert into nfe_fornecedor_oculto (cnpj, nome, motivo) values ('00000000000000','NOME','PJ');
-- Voltar a mostrar:   delete from nfe_fornecedor_oculto where cnpj = '00000000000000';
-- Ver a lista:        select * from nfe_fornecedor_oculto order by nome;
create table if not exists public.nfe_fornecedor_oculto (
  cnpj text primary key, nome text, motivo text, ocultado_em timestamptz not null default now());
alter table public.nfe_fornecedor_oculto enable row level security;
revoke all on public.nfe_fornecedor_oculto from anon, authenticated;

create or replace function public.nfe_oculta(p_cnpj text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.nfe_fornecedor_oculto where cnpj = p_cnpj) $$;
create or replace function public.nfe_id_oculto(p_id bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.nfe_master m join public.nfe_fornecedor_oculto o on o.cnpj = m.fornecedor_cnpj where m.id = p_id) $$;
revoke execute on function public.nfe_oculta(text), public.nfe_id_oculto(bigint) from public, anon;
grant execute on function public.nfe_oculta(text), public.nfe_id_oculto(bigint) to authenticated;

alter policy leitura_publica on public.nfe_master to authenticated using (not public.nfe_oculta(fornecedor_cnpj));
alter policy leitura_publica on public.nfe_master_itens to authenticated using (not public.nfe_id_oculto(nfe_id));

-- cruzamento com a SD1 (mv_nfe_sd1 não aceita RLS): o painel lê esta view filtrada
create or replace view public.nfe_sd1_painel as
  select s.* from public.mv_nfe_sd1 s where not public.nfe_id_oculto(s.nfe_id);
revoke all on public.nfe_sd1_painel from anon;
grant select on public.nfe_sd1_painel to authenticated;
revoke select on public.mv_nfe_sd1, public.vw_nfe_sd1 from authenticated;
