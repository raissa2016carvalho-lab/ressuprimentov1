-- Compras: tabelas prontas + funções de resumo (1ª entrega: Solicitações, Pedidos, Indicadores)
-- Rodar no Supabase SQL Editor. Desfazer no fim do arquivo.

-- 1) Tabelas prontas (só as colunas que a tela usa, datas como date, nome da filial resolvido)
create materialized view public.mv_compras_sc as
select s."C1_NUM" num, s."C1_ITEM" item, s."C1_FILIAL" filial, trim(s."C1_FILIAL") fil,
       coalesce(f.nome_filial, trim(s."C1_FILIAL")) filial_nome,
       nullif(s."C1_EMISSAO",'')::date dt, s."C1_EMISSAO" emissao, s."C1_YDTAPRO" aprov,
       s.tipo_sc, s."C1_GRPRD" grp, s."C1_SOLICIT" solicit, s."C1_CC" cc, s."C1_NOMAPRO" nomapro,
       s."STATUS_DESC" status_desc, s.comprador, s.temp_atendimento
from public.scs s
left join public.filiais f on ltrim(f.filial,'0') = ltrim(trim(s."C1_FILIAL"),'0');
create unique index mv_compras_sc_pk on public.mv_compras_sc (num, item, filial);
create index mv_compras_sc_dt on public.mv_compras_sc (dt);

create materialized view public.mv_compras_ped as
select p."C7_NUM" num, p."C7_FILIAL" filial, trim(p."C7_FILIAL") fil,
       coalesce(nullif(trim(p."DESC_FILIAL"),''), f.nome_filial, trim(p."C7_FILIAL")) filial_nome,
       p."C7_GRPPROD" grp, p."DESC_GRPPROD" desc_grp, p."Comp" comp, p."FORNECEDOR" fornecedor, p."COND_PAG" cond_pag,
       nullif(p."EMISSAO_PEDIDO",'')::date dt, p."EMISSAO_PEDIDO" emissao, p."TIPO_PEDIDO" tipo_pedido, p."SEM_SC" sem_sc,
       p."STATUS_PEDIDO" status_pedido, p."C7_TOTAL" total, p.leadtime_dias, p.tempo_pagamento
from public.pedidos p
left join public.filiais f on ltrim(f.filial,'0') = ltrim(trim(p."C7_FILIAL"),'0');
create unique index mv_compras_ped_pk on public.mv_compras_ped (num, filial);
create index mv_compras_ped_dt on public.mv_compras_ped (dt);

grant select on public.mv_compras_sc, public.mv_compras_ped to anon, authenticated;

-- 2) Resumo de uma vez (indicadores, tabelas e gráficos das abas Solicitações, Pedidos e Indicadores)
--    Mesmas regras da tela antiga: nota sem data passa no filtro de período; vazio vira "N/A".
create or replace function public.compras_resumo(p_ini date default null, p_fim date default null, p_comp text default null,
  p_grp text default null, p_tipo text default null, p_fil text default null)
returns json language sql stable set search_path = public as $$
with s as materialized (
  select * from mv_compras_sc
  where (p_ini is null or dt is null or dt >= p_ini) and (p_fim is null or dt is null or dt <= p_fim)
    and (p_comp is null or comprador = p_comp) and (p_grp is null or grp = p_grp)
    and (p_tipo is null or tipo_sc = p_tipo) and (p_fil is null or fil = trim(p_fil))
), p as materialized (
  select * from mv_compras_ped
  where (p_ini is null or dt is null or dt >= p_ini) and (p_fim is null or dt is null or dt <= p_fim)
    and (p_comp is null or comp = p_comp) and (p_grp is null or grp = p_grp)
    and (p_fil is null or fil = trim(p_fil))
)
select json_build_object(
  'sc', (select json_build_object('total', count(*), 'urg', count(*) filter (where tipo_sc = 'URGENCIA'),
           'tempo_medio', avg(temp_atendimento),
           'atendida',  count(*) filter (where status_desc like '%Totalmente Atendida%'),
           'parcial',   count(*) filter (where status_desc like '%Parcialmente%'),
           'pendente',  count(*) filter (where status_desc like '%Pendente%'),
           'bloqueada', count(*) filter (where status_desc like '%Bloqueada%'),
           'rejeitada', count(*) filter (where lower(status_desc) like '%rejeitada%'),
           'eliminada', count(*) filter (where status_desc like '%Resíduo%')) from s),
  'sc_solicit', (select json_agg(json_build_array(k, n) order by n desc, k) from (select coalesce(nullif(solicit,''),'N/A') k, count(*) n from s group by 1 order by 2 desc, 1 limit 20) x),
  'sc_aprov',   (select json_agg(json_build_array(k, n) order by n desc, k) from (select coalesce(nullif(nomapro,''),'N/A') k, count(*) n from s group by 1 order by 2 desc, 1 limit 20) x),
  'sc_comp',    (select json_agg(json_build_array(k, n) order by n desc, k) from (select coalesce(nullif(comprador,''),'N/A') k, count(*) n from s group by 1) x),
  'sc_tipo',    (select json_agg(json_build_array(k, n) order by n desc, k) from (select coalesce(nullif(tipo_sc,''),'N/A') k, count(*) n from s group by 1) x),
  'sc_cc',      (select json_agg(json_build_array(k, n) order by n desc, k) from (select coalesce(nullif(cc,''),'N/A') k, count(*) n from s group by 1 order by 2 desc, 1 limit 20) x),
  'sc_status',  (select json_agg(json_build_array(k, n) order by n desc, k) from (select coalesce(nullif(status_desc,''),'N/A') k, count(*) n from s group by 1) x),
  'sc_mes',     (select json_agg(json_build_array(k, n) order by k) from (select to_char(dt,'YYYY-MM') k, count(*) n from s where dt is not null group by 1 order by 1 desc limit 12) x),
  'ped', (select json_build_object('total', count(*), 'valor', coalesce(sum(total),0),
           'normal', coalesce(sum(total) filter (where tipo_pedido = 'NORMAL'),0),
           'urgente', coalesce(sum(total) filter (where tipo_pedido in ('URGENCIA','URGÊNCIA')),0),
           'regular', coalesce(sum(total) filter (where tipo_pedido in ('REGULARIZACAO','REGULARIZAÇÃO')),0),
           'sem_sc', count(*) filter (where sem_sc = 'SEM SC'), 'com_sc', count(*) filter (where sem_sc = 'COM SC'),
           'valor_sem_sc', coalesce(sum(total) filter (where sem_sc = 'SEM SC'),0), 'valor_com_sc', coalesce(sum(total) filter (where sem_sc = 'COM SC'),0),
           'lead_medio', avg(leadtime_dias) filter (where leadtime_dias >= 0)) from p),
  'ped_comp',   (select json_agg(json_build_array(k, v, n) order by v desc, k) from (select coalesce(nullif(comp,''),'N/A') k, coalesce(sum(total),0) v, count(*) n from p group by 1) x),
  'ped_filial', (select json_agg(json_build_array(k, v, n) order by v desc, k) from (select coalesce(nullif(filial_nome,''),'N/A') k, coalesce(sum(total),0) v, count(*) n from p group by 1) x),
  'ped_tipo',   (select json_agg(json_build_array(k, v, n) order by v desc, k) from (select coalesce(nullif(tipo_pedido,''),'N/A') k, coalesce(sum(total),0) v, count(*) n from p group by 1) x),
  'ped_forn',   (select json_agg(json_build_array(k, v, n) order by v desc, k) from (select coalesce(nullif(fornecedor,''),'N/A') k, coalesce(sum(total),0) v, count(*) n from p group by 1 order by 2 desc, 1 limit 15) x),
  'ped_grupo',  (select json_agg(json_build_array(k, v, n) order by v desc, k) from (select coalesce(nullif(trim(coalesce(grp,'') || ' — ' || coalesce(desc_grp,'')),'—'),'N/A') k, coalesce(sum(total),0) v, count(*) n from p group by 1 order by 2 desc, 1 limit 15) x),
  'ped_status', (select json_agg(json_build_array(k, n) order by n desc, k) from (select coalesce(nullif(status_pedido,''),'N/A') k, count(*) n from p group by 1) x),
  'ped_mes',    (select json_agg(json_build_array(k, v) order by k) from (select to_char(dt,'YYYY-MM') k, coalesce(sum(total),0) v from p where dt is not null group by 1 order by 1 desc limit 12) x),
  'ped_lead',   (select json_agg(json_build_array(k, v) order by v desc, k) from (select coalesce(nullif(comp,''),'N/A') k, avg(leadtime_dias) v from p where leadtime_dias >= 0 and leadtime_dias < 365 group by 1) x),
  'ped_pag',    (select json_agg(json_build_array(k, v) order by v desc, k) from (select coalesce(nullif(comp,''),'N/A') k, avg(tempo_pagamento) v from p where tempo_pagamento >= 0 and tempo_pagamento < 365 group by 1) x)
)
$$;

-- 3) Listas paginadas (20 por página), com a mesma busca da tela
create or replace function public.compras_lista_sc(p_ini date default null, p_fim date default null, p_comp text default null,
  p_grp text default null, p_tipo text default null, p_fil text default null, p_q text default null, p_pag int default 1, p_por int default 20)
returns json language sql stable set search_path = public as $$
with s as materialized (
  select * from mv_compras_sc
  where (p_ini is null or dt is null or dt >= p_ini) and (p_fim is null or dt is null or dt <= p_fim)
    and (p_comp is null or comprador = p_comp) and (p_grp is null or grp = p_grp)
    and (p_tipo is null or tipo_sc = p_tipo) and (p_fil is null or fil = trim(p_fil))
    and (coalesce(p_q,'') = '' or num ilike '%'||p_q||'%' or solicit ilike '%'||p_q||'%' or cc ilike '%'||p_q||'%'
         or comprador ilike '%'||p_q||'%' or filial_nome ilike '%'||p_q||'%')
)
select json_build_object('total', (select count(*) from s),
  'rows', (select json_agg(r) from (select num, emissao, aprov, tipo_sc, grp, filial_nome, solicit, cc, comprador, temp_atendimento
           from s order by num, item, filial limit greatest(p_por,1) offset (greatest(p_pag,1)-1)*greatest(p_por,1)) r))
$$;

create or replace function public.compras_lista_ped(p_ini date default null, p_fim date default null, p_comp text default null,
  p_grp text default null, p_fil text default null, p_q text default null, p_pag int default 1, p_por int default 20)
returns json language sql stable set search_path = public as $$
with p as materialized (
  select * from mv_compras_ped
  where (p_ini is null or dt is null or dt >= p_ini) and (p_fim is null or dt is null or dt <= p_fim)
    and (p_comp is null or comp = p_comp) and (p_grp is null or grp = p_grp) and (p_fil is null or fil = trim(p_fil))
    and (coalesce(p_q,'') = '' or num ilike '%'||p_q||'%' or fornecedor ilike '%'||p_q||'%' or comp ilike '%'||p_q||'%'
         or filial_nome ilike '%'||p_q||'%')
)
select json_build_object('total', (select count(*) from p),
  'rows', (select json_agg(r) from (select num, emissao, filial_nome, fornecedor, comp, total, cond_pag, tipo_pedido, sem_sc, leadtime_dias
           from p order by num, filial limit greatest(p_por,1) offset (greatest(p_pag,1)-1)*greatest(p_por,1)) r))
$$;

-- 4) Opções dos filtros (comprador, grupo, tipo, filial)
create or replace function public.compras_opcoes()
returns json language sql stable set search_path = public as $$
select json_build_object(
  'comps',   (select json_agg(v order by v) from (select comprador v from mv_compras_sc where coalesce(comprador,'') <> '' union select comp from mv_compras_ped where coalesce(comp,'') <> '') x),
  'grps',    (select json_agg(v order by v) from (select grp v from mv_compras_sc where coalesce(grp,'') <> '' union select grp from mv_compras_ped where coalesce(grp,'') <> '') x),
  'tipos',   (select json_agg(v order by v) from (select distinct tipo_sc v from mv_compras_sc where coalesce(tipo_sc,'') <> '') x),
  'filiais', (select json_agg(json_build_array(v, n) order by v) from (select filial v, min(filial_nome) n from (select filial, filial_nome from mv_compras_sc union all select filial, filial_nome from mv_compras_ped) y where coalesce(filial,'') <> '' group by 1) x),
  'atualizado', now())
$$;

grant execute on function public.compras_resumo(date,date,text,text,text,text) to anon, authenticated;
grant execute on function public.compras_lista_sc(date,date,text,text,text,text,text,int,int) to anon, authenticated;
grant execute on function public.compras_lista_ped(date,date,text,text,text,text,int,int) to anon, authenticated;
grant execute on function public.compras_opcoes() to anon, authenticated;

-- 5) Atualização das tabelas prontas (chamada no fim do upload_compras.py)
create or replace function public.atualizar_compras() returns void language sql security definer set search_path = public as $$
  refresh materialized view concurrently public.mv_compras_sc;
  refresh materialized view concurrently public.mv_compras_ped;
$$;
revoke execute on function public.atualizar_compras() from public, anon, authenticated;
grant execute on function public.atualizar_compras() to service_role;

-- DESFAZER:
-- drop function if exists public.atualizar_compras();
-- drop function if exists public.compras_opcoes();
-- drop function if exists public.compras_lista_ped(date,date,text,text,text,text,int,int);
-- drop function if exists public.compras_lista_sc(date,date,text,text,text,text,text,int,int);
-- drop function if exists public.compras_resumo(date,date,text,text,text,text);
-- drop materialized view if exists public.mv_compras_ped;
-- drop materialized view if exists public.mv_compras_sc;
