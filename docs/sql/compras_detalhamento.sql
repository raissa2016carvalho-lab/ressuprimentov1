-- Compras — 3ª entrega: aba Detalhamento rápida
-- Tabela pronta com cada item de SC já amarrado ao pedido (nº da SC + filial), e uma função que devolve
-- só a página da tela + os indicadores, com os filtros aplicados no banco. A tela não baixa mais as 107 mil SCs.
-- Rodar no Supabase SQL Editor. Desfazer no fim do arquivo.

create materialized view public.mv_compras_det as
-- 11/11: status do pedido POR ITEM (antes pegava um pedido só por SC e repetia o status em todos os itens)
with pci as (   -- item do pedido: SC + filial + produto + nº do pedido
  select distinct on (trim(c7_numsc), trim(c7_filial), trim(c7_produto), trim(c7_num))
         trim(c7_numsc) numsc, trim(c7_filial) fil, trim(c7_produto) prod, trim(c7_num) num, c7_emissao emissao, status_desc st
  from public.pedidos_compra where coalesce(trim(c7_numsc),'') <> ''
  order by trim(c7_numsc), trim(c7_filial), trim(c7_produto), trim(c7_num), c7_emissao desc
),
pci2 as (select distinct on (numsc, fil, prod) * from pci order by numsc, fil, prod, emissao desc),   -- item sem nº de pedido na SC
ped as (        -- pedido inteiro (quando o item não é achado no pedido)
  select distinct on (trim("C7_NUM"), trim("C7_FILIAL")) trim("C7_NUM") num, trim("C7_FILIAL") fil, "EMISSAO_PEDIDO" emissao, "STATUS_PEDIDO" st
  from public.pedidos order by trim("C7_NUM"), trim("C7_FILIAL"), "EMISSAO_PEDIDO" desc nulls last
),
j as (
  select s.*, nullif(trim(s.pedido_num),'') pn, p1.st st1, p1.emissao em1, p2.st st2, p2.num num2, p2.emissao em2, pd.st st3, pd.emissao em3
  from public.scs s
  left join pci p1 on p1.numsc = trim(s."C1_NUM") and p1.fil = trim(s."C1_FILIAL") and p1.prod = trim(s."C1_PRODUTO") and p1.num = trim(s.pedido_num)
  left join pci2 p2 on p2.numsc = trim(s."C1_NUM") and p2.fil = trim(s."C1_FILIAL") and p2.prod = trim(s."C1_PRODUTO")
  left join ped pd on pd.num = coalesce(nullif(trim(s.pedido_num),''), p2.num) and pd.fil = trim(s."C1_FILIAL")
)
select j."C1_NUM" num_sc, j."C1_ITEM" item, trim(j."C1_FILIAL") fil,
       coalesce(nullif(trim(f.nome_filial),''), trim(j."C1_FILIAL")) filial,
       j."C1_GRPRD" grupo, j."C1_EMISSAO" emissao_sc, nullif(j."C1_EMISSAO",'')::date dt, j."C1_YDTAPRO" aprov_sc,
       coalesce(nullif(j."C1_DESCRI",''),'–') descricao, coalesce(j."C1_OBS",'') obs, j."C1_QUANT" quant,
       coalesce(nullif(j."STATUS_DESC",''),'–') status_sc,
       coalesce(j.pn, case when j.st2 is not null then j.num2 end, '–') num_ped,
       coalesce(j.em1, case when j.pn is null then j.em2 end, j.em3) emissao_ped,
       case when coalesce(j.st1, case when j.pn is null then j.st2 end, j.st3) is null
            then case when j.pn is not null then '–' else 'SEM PEDIDO' end
            else case upper(coalesce(j.st1, case when j.pn is null then j.st2 end, j.st3))
                   when 'RECEBIDO' then 'Recebido' when 'RECEBIDO PARCIALMENTE' then 'Recebido parcialmente'
                   when 'PENDENTE' then 'Pendente' when 'PC ELIMINADO POR RESÍDUO' then 'PC Eliminado por Resíduo'
                   when 'REJEITADO PELO APROVADOR' then 'Rejeitado pelo aprovador' when 'EM APROVAÇÃO' then 'Em aprovação'
                   when 'EM RECEBIMENTO (PRÉ-NOTA)' then 'Em recebimento (Pré-nota)' when 'PEDIDO DE CONTRATO (GCT)' then 'Pedido de Contrato (GCT)'
                   when 'SEM STATUS' then 'Sem status'
                   else coalesce(j.st1, case when j.pn is null then j.st2 end, j.st3) end end status_ped,
       coalesce(j.pedido_total,0) valor, j.comprador, j.tipo_sc tipo,
       lower(coalesce(f.nome_filial,'')||' '||coalesce(j."C1_DESCRI",'')||' '||coalesce(j."C1_OBS",'')||' '||coalesce(j.comprador,'')) busca
from j
left join public.filiais f on ltrim(f.filial,'0') = ltrim(trim(j."C1_FILIAL"),'0');
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
