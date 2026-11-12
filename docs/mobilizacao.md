# Mobilização (aba do index.html)

## Tela
- Botão **🔎 Filtrar mobilizações**: seleção múltipla, busca, "Marcar os encontrados", **🧹 Limpar tudo**.
  A escolha fica no navegador. Só as visíveis carregam o resumo de SCs.
- Com filtro ativo: card do **% total** (soma dos itens das filtradas; mesma regra do card de cada uma:
  recebidos + via estoque ÷ itens, sem eliminados por resíduo).
- Coluna de pedidos mostra `SC 000121 · PC 000214 · Pendente` ou `SC 000121 · sem pedido`.
- As SCs vêm de `sc_pedidos_v2` (alimentada pelo `sync_sc_pedidos_v2.py`), por `sc_numero` + filial.
- Fardamento fica em mobilização **separada** (como #29 e #30).

## Ondas ENEL SP (TESTE) — criadas em 22–23/10/2026
Fonte: planilha "Mobilização São Paulo Enel 3", abas CONSTRUÇÃO, LINHA VIVA e SKY, coluna de
**quantidade** (não a multiplicada). Quantidade é **por pessoa da função**:
- Construção: chefe ×1, motorista ×1, eletricista ×4
- Linha Viva: chefe ×1, eletricista ×3 (um eletricista recebe a ficha do chefe)
- SKY: chefe ×1, eletricista ×2 (idem)

| # | Card | Equipes |
|---|---|---|
| 38 | 1ª ONDA ENEL SP - LINHA VIVA (2 EQ) (TESTE) | 2 |
| 39 | 1ª ONDA ENEL SP - CONSTRUÇÃO (2 EQ) (TESTE) | 2 |
| 40 | 1ª ONDA ENEL SP - SKY (1 EQ) (TESTE) | 1 |
| 41 | 2ª ONDA ENEL SP - LINHA VIVA (1 EQ) (TESTE) | 1 |
| 42 | 2ª ONDA ENEL SP - CONSTRUÇÃO (4 EQ) (TESTE) | 4 |
| 43 | 2ª ONDA ENEL SP - SKY (2 EQ) (TESTE) | 2 |

3ª onda (5 construção, 1 SKY, 1 LV) **ainda não foi criada**.

**27/10 — 1 equipe SKY antecipada da 2ª para a 1ª onda:** #40 virou "1ª ONDA ENEL SP - SKY (2 EQ) (TESTE)" (2 equipes, 946 peças,
estoque 9 un — recebeu as 3 un da #43: trado, escova de aço, chave de fenda 5/16") e #43 virou "2ª ONDA ENEL SP - SKY (1 EQ) (TESTE)"
(1 equipe, 473 peças, sem estoque). A SC 000125 da #40 cobre só 1 equipe: **falta abrir SC para a 2ª equipe e associar no card**.
Backup: `backup_mob_40_43_2026_10_27_mob`, `_itens`, `_estoque` (desfazer = voltar desses backups).

- **Estoque**: copiado (sem remover) do estoque registrado na **#28** (75 itens, 864 un.), em ordem:
  1ª onda antes da 2ª; dentro da onda Linha Viva → Construção → SKY. Usado: 651 un. na 1ª, 121 na 2ª.
- Itens sem código na planilha ficaram de fora (uniformes sem tamanho, FROTA/TI, manga e luva de borracha sem número).
- **SCs associadas** (em 23/10): #38 = 000117, #39 = 000114, #40 = 000125. Faltam 000121 e 000124 e a 2ª onda.
- ⚠️ SCs 000114, 000117 e 000121 também estão ligadas às antigas #27 e #28 (risco de contar a mesma entrega duas vezes).

## Marcar pedido como recebido manualmente (`pedido_recebido_manual`) — 12/11
- No detalhe da mobilização, bloco **"Pedidos desta mobilização (N) · X sem entrada"** (abre sozinho se tiver pendente),
  com cada PC, filial, SC e status. Botão **✓ Marcar recebido** (só admin; pede motivo opcional) e **Desfazer**.
- O pedido marcado passa a valer como **"Recebido (manual)"** no % do card (`carregarResumosMob`) e nos itens do detalhe
  (`renderDetalheMob`), igual a um recebido do Protheus. **Não altera o Protheus**: se o Protheus der entrada depois,
  continua recebido; o "Desfazer" volta a seguir o status do Protheus.
- A marcação é por **filial + nº do pedido** (vale para todas as mobilizações que usam o pedido). Grava quem marcou e quando.
```sql
create table public.pedido_recebido_manual (
  filial text not null,
  pc_numero text not null,
  recebido_por text,
  recebido_em timestamptz default now(),
  motivo text,
  mobilizacao_id bigint,
  primary key (filial, pc_numero)
);
alter table public.pedido_recebido_manual enable row level security;
create policy prm_ler on public.pedido_recebido_manual for select to anon, authenticated using (true);
create policy prm_gravar on public.pedido_recebido_manual for insert to authenticated with check (true);
create policy prm_alterar on public.pedido_recebido_manual for update to authenticated using (true) with check (true);
create policy prm_apagar on public.pedido_recebido_manual for delete to authenticated using (true);
-- desfazer: drop table public.pedido_recebido_manual;
```

## Mobilizações antigas (não mexer)
#3, 4, 6, 9, 11, 13, 14, 15, 20, 24, 26, 27, 28, 29, 30. As #31–35 foram apagadas (backup guardado).

## Tela de Separação (`separacao.html`, 04/11 — no Preview)
Ideia trazida por um amigo da Raissa (repositório `eemanyu/separacao-epi-epc`, servidor Node próprio + webhook); foi refeita **dentro
do nosso sistema**, sem servidor novo. Login do Painel principal. Lista as mobilizações (sem grupo "OCULTO") com X/Y itens conferidos;
na mobilização, item por código (soma das funções): ✓ Tem / ✕ Não tem, qtd separada (vem o solicitado), patrimônios, observação.
Cada mudança grava na hora em `mobilizacao_estoque` (upsert `mobilizacao_id,codigo`) com `separado_por/separado_em` → aparece na
coluna Estoque do card. "Concluir" exige todos conferidos e trava (`mobilizacoes.sep_status = 'concluida'`); só admin reabre.
Estoque lançado antes da tela (qtd > 0 sem marcação) conta como "Tem" ("já lançado no card"). Itens sem código não aparecem.
