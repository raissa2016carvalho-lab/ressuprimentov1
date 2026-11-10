-- Notas de serviço (NFS-e) no painel de Notas — 11/11
-- As NFS-e entram na tabela nfe_master (id negativo, modelo 'NFSE') pelo sync_nfe_master.py.
-- Cruzamento com a SD1: NFS-e não tem chave de NF-e na SD1 nem série igual; regra extra (só para NFS-e):
-- filial + número + emissão + CNPJ do prestador.
create or replace view public.vw_nfe_sd1 as
 WITH s AS MATERIALIZED (
         SELECT movimentos_entrada.filial,
            ltrim(movimentos_entrada.nota_fiscal, '0'::text) AS doc,
            COALESCE(NULLIF(ltrim(movimentos_entrada.serie, '0'::text), ''::text), '0'::text) AS ser,
            movimentos_entrada.emissao,
            movimentos_entrada.fornecedor,
            max(NULLIF(movimentos_entrada.chave_nfe, ''::text)) AS chave,
            max(NULLIF(regexp_replace(COALESCE(movimentos_entrada.fornecedor_cnpj, ''::text), '\D'::text, ''::text, 'g'::text), ''::text)) AS cnpj,
            min(NULLIF(movimentos_entrada.dtdigit, ''::text)) AS dtdigit,
            count(*) AS itens,
            sum(movimentos_entrada.valor_entrada) AS valor,
            string_agg(DISTINCT movimentos_entrada.tes, ','::text) AS tes
           FROM movimentos_entrada
          GROUP BY movimentos_entrada.filial, (ltrim(movimentos_entrada.nota_fiscal, '0'::text)), COALESCE(NULLIF(ltrim(movimentos_entrada.serie, '0'::text), ''::text), '0'::text), movimentos_entrada.emissao, movimentos_entrada.fornecedor
        ), n AS MATERIALIZED (
         SELECT nfe_master.id,
            nfe_master.chave,
            nfe_master.filial,
            (nfe_master.numero)::text AS doc,
            COALESCE(NULLIF((nfe_master.serie)::text, '0'::text), '0'::text) AS ser,
            to_char(nfe_master.emissao, 'YYYYMMDD'::text) AS emi,
            regexp_replace(COALESCE(nfe_master.fornecedor_cnpj, ''::text), '\D'::text, ''::text, 'g'::text) AS cnpj,
            COALESCE(nfe_master.modelo, ''::text) AS modelo
           FROM nfe_master
          WHERE (nfe_master.status_nfe <> 'C'::text)
        ), c AS (
         SELECT n.id, s.filial, s.doc, s.ser, s.emissao, s.fornecedor, s.chave, s.cnpj, s.dtdigit, s.itens, s.valor, s.tes,
            1 AS pri, 'chave'::text AS amarracao
           FROM (n JOIN s ON ((s.chave = n.chave)))
        UNION ALL
         SELECT n.id, s.filial, s.doc, s.ser, s.emissao, s.fornecedor, s.chave, s.cnpj, s.dtdigit, s.itens, s.valor, s.tes,
            2, 'filial+nota+série+emissão+CNPJ'::text
           FROM (n JOIN s ON (((s.filial = n.filial) AND (s.doc = n.doc) AND (s.ser = n.ser) AND (s.emissao = n.emi) AND (s.cnpj = n.cnpj))))
          WHERE (s.chave IS NULL)
        UNION ALL
         SELECT n.id, s.filial, s.doc, s.ser, s.emissao, s.fornecedor, s.chave, s.cnpj, s.dtdigit, s.itens, s.valor, s.tes,
            3, 'filial+nota+série+emissão'::text
           FROM (n JOIN s ON (((s.filial = n.filial) AND (s.doc = n.doc) AND (s.ser = n.ser) AND (s.emissao = n.emi))))
          WHERE ((s.chave IS NULL) AND (s.cnpj IS NULL))
        UNION ALL
         SELECT n.id, s.filial, s.doc, s.ser, s.emissao, s.fornecedor, s.chave, s.cnpj, s.dtdigit, s.itens, s.valor, s.tes,
            4, 'NFS-e: filial+nota+emissão+CNPJ'::text
           FROM (n JOIN s ON (((s.filial = n.filial) AND (s.doc = n.doc) AND (s.emissao = n.emi) AND (s.cnpj = n.cnpj))))
          WHERE (n.modelo = 'NFSE'::text)
        )
 SELECT DISTINCT ON (id) id AS nfe_id,
    emissao AS sd1_emissao,
    dtdigit AS sd1_dtdigit,
    itens AS sd1_itens,
    valor AS sd1_valor,
    fornecedor AS sd1_fornecedor,
    tes AS sd1_tes,
    amarracao
   FROM c
  ORDER BY id, pri;

-- DESFAZER: rodar de novo a definição anterior (sem a regra 4 e sem a coluna modelo no bloco n) —
-- está no histórico do repositório (docs/sql/nfse.sql, versão anterior = definição atual do banco em 10/11).

-- ── Rodapé da nota e pedido do cliente (11/11, aplicado) ─────────────────────────────────
alter table public.nfe_master add column if not exists rodape text, add column if not exists rodape_fisco text,
  add column if not exists pedido_cliente text;
create index if not exists nfe_master_rodape_trgm on public.nfe_master using gin (lower(coalesce(rodape,'')) gin_trgm_ops);
-- DESFAZER: drop index if exists nfe_master_rodape_trgm; alter table public.nfe_master drop column rodape, drop column rodape_fisco, drop column pedido_cliente;

-- ── Data de entrega do pedido para o painel de Notas (11/11, aplicado) ───────────────────
create or replace function public.nfe_entregas()
returns table(nfe_id bigint, pedido text, entrega date)
language sql stable security definer set search_path = public as $$
  with np as (
    select n.id, n.filial,
           lpad(regexp_replace(coalesce(nullif(trim(f.pedido),''), n.pedido_cliente),'\D','','g'),6,'0') ped
    from nfe_master n left join nfe_fluxo f on f.nfe_id = n.id
    where coalesce(nullif(trim(f.pedido),''), n.pedido_cliente) is not null
      and n.emissao >= now() - interval '400 days'
  ),
  pe as (select trim("C7_NUM") num, trim("C7_FILIAL") fil, min(nullif("ENTREGA_PEDIDO",'')::date) entrega
         from pedidos group by 1,2)
  select np.id, np.ped, pe.entrega from np join pe on pe.num = np.ped and pe.fil = np.filial
$$;
grant execute on function public.nfe_entregas() to authenticated;
-- DESFAZER: drop function if exists public.nfe_entregas();
