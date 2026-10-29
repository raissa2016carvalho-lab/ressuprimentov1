# NFe Master (HMIT) → Supabase

Objetivo: medir o **atraso entre a emissão da NF e a entrada no Protheus**, por filial e por setor,
e depois ligar com a SD1 (`movimentos_entrada`) e com os pedidos.

## Origem
- Banco PostgreSQL do NFe Master: `192.168.1.13:5432`, banco `nfemaster` (rede interna → o sync roda no PC da Raissa).
- `nfemanager.tb_nfe` (cabeçalho, ~65 mil notas) + `nfemanager.tb_empresanfe` (filial destinatária)
  + `protheus.tb_integracaoprotheusnfe` (status no Protheus, pedido, código Protheus do fornecedor).
- Filial: os 4 dígitos depois da barra do CNPJ da empresa (`/0007` → 07 Sobral). O campo
  `codigofilialerp` do NFe Master está vazio/errado — não usar.

## Códigos (a confirmar com notas de exemplo)
- `statusintegracao`: 3 (45 mil) / 2 (19 mil) / 1 (484) → provável Integrado / Associado / Pendente.
- `statusnfe`: A autorizada, C cancelada, D denegada, V = ?
- Manifestação (SEFAZ): 210200 confirmação, 210210 ciência, 210220 desconhecimento, 210240 operação não realizada.

## Passo 1 — tabela `nfe_master` (rodar no SQL Editor)
```sql
create table public.nfe_master (
  id bigint primary key,
  chave text, numero bigint, serie bigint, modelo text,
  filial text, empresa_nome text, empresa_cnpj text,
  fornecedor_cnpj text, fornecedor_nome text, fornecedor_fantasia text, fornecedor_uf text,
  fornecedor_cod text, fornecedor_loja text,
  emissao timestamp, autorizacao timestamp, chegada timestamp, integracao timestamp, alterado timestamp,
  status_nfe text, status_integracao text, status_protheus text, msg_protheus text, pedido text,
  tipo_operacao text, natureza text, valor_total numeric, valor_produtos numeric,
  em_tratativa boolean, motivo_tratativa text, data_tratativa timestamp, erro_integracao text,
  manifestacao text, data_manifestacao timestamp,
  atualizado_em timestamptz default now()
);
create index nfe_master_filial_emissao on public.nfe_master (filial, emissao);
create index nfe_master_fornecedor on public.nfe_master (fornecedor_cnpj);
create index nfe_master_chave on public.nfe_master (chave);
alter table public.nfe_master enable row level security;
create policy leitura_publica on public.nfe_master for select to anon, authenticated using (true);
-- desfazer: drop table public.nfe_master;
```

## Passo 1 — sync
`scripts/sync_nfe_master.py` (copiar para `C:\painel-protheus`, preencher usuário/senha/chave).
1ª vez carrega desde 01/01/2025; depois revisa só o que mudou nos últimos 3 dias (upsert, não apaga).

## Passo 2 — setor (tela notas.html)
- `fornecedor_setor` (cnpj → setor padrão) e `nfe_setor` (nfe_id → setor da nota). O setor da nota vale mais que o
  do fornecedor. Tela abre por nota, com seleção de várias notas para aplicar o setor de uma vez.
```sql
create table public.nfe_setor (nfe_id bigint primary key, setor text, atualizado_em timestamptz default now(), atualizado_por text);
alter table public.nfe_setor enable row level security;
create policy nfe_setor_ler on public.nfe_setor for select to anon, authenticated using (true);
create policy nfe_setor_gravar on public.nfe_setor for insert to authenticated with check (true);
create policy nfe_setor_alterar on public.nfe_setor for update to authenticated using (true) with check (true);
create policy nfe_setor_apagar on public.nfe_setor for delete to authenticated using (true);
-- desfazer: drop table public.nfe_setor;
```

## Itens das notas (`nfe_master_itens`) — popup na tela
O sync manda também os itens (tb_nfeitem) + o que foi associado no Protheus (produto, PC, CC).
```sql
create table public.nfe_master_itens (
  id bigint primary key, nfe_id bigint, item bigint, codigo_forn text, descricao text, ncm text, cfop text,
  unidade text, quantidade numeric, valor_unit numeric, valor_total numeric, pedido_xml text, item_pedido_xml bigint,
  cod_protheus text, desc_protheus text, pc text, item_pc text, cc text, qtd_associada numeric,
  atualizado_em timestamptz default now()
);
create index nfe_master_itens_nfe on public.nfe_master_itens (nfe_id);
alter table public.nfe_master_itens enable row level security;
create policy leitura_publica on public.nfe_master_itens for select to anon, authenticated using (true);
-- desfazer: drop table public.nfe_master_itens;
```
Tela abre com: só pendentes (não integradas) + manifestação "Ciência da operação".

## Cruzamento com a SD1 (`vw_nfe_sd1`) — double check de lançamento manual
Liga nota do NFe Master × `movimentos_entrada` por filial + nº da nota (sem zeros à esquerda) + série.
Validação (2026): 5.309 de 5.312 notas integradas acharam a SD1; 736 "pendentes" já estavam na SD1 (lançamento manual).
Com a regra da mesma emissão: 1.174 ligações (175 eram de outro fornecedor com o mesmo nº). Ideal: trazer F1_CHVNFE na SD1.
```sql
create index if not exists movimentos_entrada_nota on public.movimentos_entrada (filial, (ltrim(nota_fiscal,'0')));
create or replace view public.vw_nfe_sd1 with (security_invoker = true) as
select n.id as nfe_id, x.*
from public.nfe_master n
cross join lateral (
  select min(m.emissao) sd1_emissao, count(*) sd1_itens, sum(m.valor_entrada) sd1_valor,
         min(m.fornecedor) sd1_fornecedor, string_agg(distinct m.tes, ',') sd1_tes
  from public.movimentos_entrada m
  where m.filial = n.filial and ltrim(m.nota_fiscal,'0') = n.numero::text
    and coalesce(nullif(ltrim(m.serie,'0'),''),'0') = coalesce(nullif(n.serie::text,'0'),'0')
    and m.emissao = to_char(n.emissao,'YYYYMMDD')   -- mesma emissão (sem isso, NF de nº baixo casava com outro fornecedor)
) x
where n.status_integracao <> '3' and n.status_nfe <> 'C' and x.sd1_itens > 0;
grant select on public.vw_nfe_sd1 to anon, authenticated;
-- desfazer: drop view public.vw_nfe_sd1; drop index public.movimentos_entrada_nota;
```

## Cruzamento pronto `mv_nfe_sd1` (29/10)
A view `vw_nfe_sd1` levava ~24 s (limite do site 3 s). A tela lê a visão materializada `mv_nfe_sd1`, atualizada
pelo `sync_nfe_master.py` no fim de cada rodada (`atualizar_nfe_sd1()`).
```sql
create materialized view public.mv_nfe_sd1 as select * from public.vw_nfe_sd1;
create unique index mv_nfe_sd1_id on public.mv_nfe_sd1 (nfe_id);
grant select on public.mv_nfe_sd1 to anon, authenticated;
create or replace function public.atualizar_nfe_sd1() returns void language sql security definer
  set search_path = public as $$ refresh materialized view concurrently public.mv_nfe_sd1 $$;
revoke execute on function public.atualizar_nfe_sd1() from public, anon, authenticated;
grant execute on function public.atualizar_nfe_sd1() to service_role;
-- desfazer: drop function public.atualizar_nfe_sd1(); drop materialized view public.mv_nfe_sd1;
```

## Fluxo: entrega prevista (Compras) e aceite do recebimento (Almoxarifado) — `nfe_fluxo`
- notas.html: coluna "Entrega prevista" (e em lote na barra de seleção). Recebida → mostra "✓ Recebida dd/mm".
- Compras também preenche Nº do pedido e Observação (texto livre) na tela de notas.
- recebimento.html → notas.html?modo=recebimento: só mostra notas COM data do Compras. Abas "A chegar" (botões Recebi / Recusar com motivo), "Recebidas", "Recusadas". Antes: (pendente, não cancelada, não está na SD1,
  sem desconhecimento/não realizada, emitida nos últimos 90 dias, sem aceite) e "Recebidas" (aceite dado,
  ainda não integrada). Botão "✓ Recebi" grava recebido_em/recebido_por; "Desfazer" limpa. Filial fica salva no navegador.
```sql
create table public.nfe_fluxo (
  nfe_id bigint primary key,
  previsao_entrega date, previsao_por text, previsao_em timestamptz,
  recebido_em timestamptz, recebido_por text,
  pedido text, obs_compras text,
  recusado_em timestamptz, recusado_por text, motivo_recusa text,
  atualizado_em timestamptz default now()
);
alter table public.nfe_fluxo enable row level security;
create policy nfe_fluxo_ler on public.nfe_fluxo for select to anon, authenticated using (true);
create policy nfe_fluxo_gravar on public.nfe_fluxo for insert to authenticated with check (true);
create policy nfe_fluxo_alterar on public.nfe_fluxo for update to authenticated using (true) with check (true);
create policy nfe_fluxo_apagar on public.nfe_fluxo for delete to authenticated using (true);
-- desfazer: drop table public.nfe_fluxo;
```

## Próximos passos
2. Setor por fornecedor: tabela `fornecedor_setor` (cnpj → setor: compras, almoxarifado, fiscal, RH,
   frota, oficina…) preenchida pela Raissa no painel.
3. Ligar com a SD1: acrescentar no `sync_movimentos_entrada.py` chave da NF-e (F1_CHVNFE), data de
   digitação (D1_DTDIGIT), pedido/item (D1_PEDIDO, D1_ITEMPC) e CC (D1_CC).
4. Painel "Notas fiscais": notas emitidas sem entrada × dias de atraso, por filial e setor.
