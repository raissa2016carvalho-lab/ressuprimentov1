-- Compras — 3ª entrega: aba Detalhamento rápida
-- Tabela pronta com cada item de SC já amarrado ao pedido (nº da SC + filial), e uma função que devolve
-- só a página da tela + os indicadores, com os filtros aplicados no banco. A tela não baixa mais as 107 mil SCs.
-- Rodar no Supabase SQL Editor. Desfazer no fim do arquivo.

create materialized view public.mv_compras_det as
with ped as (
  -- um pedido por SC + filial (o mesmo nº de SC existe em filiais diferentes)
  select distinct on (trim("C7_NUMSC"), trim("C7_FILIAL"))
         trim("C7_NUMSC") numsc, trim("C7_FILIAL") fil, trim("C7_NUM") num, "EMISSAO_PEDIDO" emissao,
         coalesce(nullif("STATUS_PEDIDO",''),'–') st
  from public.pedidos
  where coalesce(trim("C7_NUMSC"),'') <> ''
  order by trim("C7_NUMSC"), trim("C7_FILIAL"), "EMISSAO_PEDIDO" desc nulls last
)
select s."C1_NUM" num_sc, s."C1_ITEM" item, trim(s."C1_FILIAL") fil,
       coalesce(nullif(trim(f.nome_filial),''), trim(s."C1_FILIAL")) filial,
       s."C1_GRPRD" grupo, s."C1_EMISSAO" emissao_sc, nullif(s."C1_EMISSAO",'')::date dt, s."C1_YDTAPRO" aprov_sc,
       coalesce(nullif(s."C1_DESCRI",''),'–') descricao, coalesce(s."C1_OBS",'') obs, s."C1_QUANT" quant,
       coalesce(nullif(s."STATUS_DESC",''),'–') status_sc,
       coalesce(nullif(trim(s.pedido_num),''), p.num, '–') num_ped, p.emissao emissao_ped,
       case when p.num is not null then p.st when coalesce(trim(s.pedido_num),'') <> '' then '–' else 'SEM PEDIDO' end status_ped,
       coalesce(s.pedido_total,0) valor, s.comprador, s.tipo_sc tipo,
       lower(coalesce(f.nome_filial,'')||' '||coalesce(s."C1_DESCRI",'')||' '||coalesce(s."C1_OBS",'')||' '||coalesce(s.comprador,'')) busca
from public.scs s
left join public.filiais f on ltrim(f.filial,'0') = ltrim(trim(s."C1_FILIAL"),'0')
left join ped p on p.numsc = trim(s."C1_NUM") and p.fil = trim(s."C1_FILIAL");
create unique index mv_compras_det_pk on public.mv_compras_det (num_sc, item, fil);
create index mv_compras_det_dt on public.mv_compras_det (dt);
create index mv_compras_det_busca on public.mv_compras_det using gin (busca gin_trgm_ops);

-- Página do Detalhamento + indicadores (mesmos filtros e regras da tela antiga; SC sem data passa no filtro de período)
create or replace function public.compras_det(p_ini date default null, p_fim date default null, p_comp text default null,
  p_grp text default null, p_fil text default null, p_ssc text default null, p_sped text default null,
  p_qsc text default null, p_qped text default null, p_q text default null, p_off int default 0, p_lim int default 20)
returns json language sql stable security definer set search_path = public as $$
with b as materialized (
  select * from mv_compras_det
  where (p_ini is null or dt is null or dt >= p_ini) and (p_fim is null or dt is null or dt <= p_fim)
    and (p_comp is null or comprador = p_comp) and (p_grp is null or grupo = p_grp)
    and (p_fil is null or fil = trim(p_fil))
    and (p_ssc is null or status_sc = p_ssc) and (p_sped is null or status_ped = p_sped)
    and (p_qsc is null or lower(num_sc) like '%'||lower(trim(p_qsc))||'%')
    and (p_qped is null or lower(num_ped) like '%'||lower(trim(p_qped))||'%')
    and (p_q is null or busca like '%'||lower(trim(p_q))||'%')
)
select json_build_object(
  'total', (select count(*) from b),
  'valor', (select coalesce(sum(valor),0) from b),
  'k', (select json_build_object(
          'atend',   count(*) filter (where status_sc like '%Totalmente Atendida%'),
          'parcial', count(*) filter (where status_sc like '%Parcialmente%'),
          'pend',    count(*) filter (where status_sc like '%Pendente%'),
          'bloq',    count(*) filter (where status_sc like '%Bloqueada%'),
          'rej',     count(*) filter (where lower(status_sc) like '%rejeitada%'),
          'elim',    count(*) filter (where status_sc like '%Resíduo%'),
          'semped',  count(*) filter (where status_ped = 'SEM PEDIDO'),
          'recebido',count(*) filter (where status_ped like '%Recebido%')) from b),
  'rows', (select coalesce(json_agg(x), '[]'::json) from (
             select filial, fil filial_cod, grupo, num_sc, emissao_sc, aprov_sc, descricao, obs, quant, status_sc,
                    num_ped, emissao_ped, status_ped, valor, comprador, tipo
             from b order by dt desc nulls last, num_sc desc, item
             offset greatest(p_off,0) limit least(greatest(p_lim,1),200)) x)
)
$$;

-- Listas dos filtros de status do Detalhamento
create or replace function public.compras_det_opcoes()
returns json language sql stable security definer set search_path = public as $$
  select json_build_object(
    'status_sc',  (select json_agg(s order by s) from (select distinct status_sc s from mv_compras_det) x),
    'status_ped', (select json_agg(s order by s) from (select distinct status_ped s from mv_compras_det) x))
$$;
grant execute on function public.compras_det(date,date,text,text,text,text,text,text,text,text,int,int) to anon, authenticated;
grant execute on function public.compras_det_opcoes() to anon, authenticated;

-- Atualização: o upload_compras.py chama atualizar_compras() no fim; agora atualiza também o Detalhamento
create or replace function public.atualizar_compras() returns void language sql security definer set search_path = public as $$
  refresh materialized view concurrently public.mv_compras_sc;
  refresh materialized view concurrently public.mv_compras_ped;
  refresh materialized view concurrently public.mv_compras_cmp;
  refresh materialized view concurrently public.mv_compras_det;
$$;

-- DESFAZER:
-- create or replace function public.atualizar_compras() returns void language sql security definer set search_path = public as $$
--   refresh materialized view concurrently public.mv_compras_sc;
--   refresh materialized view concurrently public.mv_compras_ped;
--   refresh materialized view concurrently public.mv_compras_cmp;
-- $$;
-- drop function if exists public.compras_det_opcoes();
-- drop function if exists public.compras_det(date,date,text,text,text,text,text,text,text,text,int,int);
-- drop materialized view if exists public.mv_compras_det;
