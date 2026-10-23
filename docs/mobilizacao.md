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

- **Estoque**: copiado (sem remover) do estoque registrado na **#28** (75 itens, 864 un.), em ordem:
  1ª onda antes da 2ª; dentro da onda Linha Viva → Construção → SKY. Usado: 651 un. na 1ª, 121 na 2ª.
- Itens sem código na planilha ficaram de fora (uniformes sem tamanho, FROTA/TI, manga e luva de borracha sem número).
- **SCs associadas** (em 23/10): #38 = 000117, #39 = 000114, #40 = 000125. Faltam 000121 e 000124 e a 2ª onda.
- ⚠️ SCs 000114, 000117 e 000121 também estão ligadas às antigas #27 e #28 (risco de contar a mesma entrega duas vezes).

## Mobilizações antigas (não mexer)
#3, 4, 6, 9, 11, 13, 14, 15, 20, 24, 26, 27, 28, 29, 30. As #31–35 foram apagadas (backup guardado).
