# Ressuprimento B&Q — Visão geral (leia primeiro)

Atualizado em 26/10/2026. Este arquivo resume o sistema, as regras de trabalho e tudo o que já foi
mudado no banco. Os detalhes de cada tela estão nos outros arquivos desta pasta:
`index.md`, `gerente.md`, `mobilizacao.md`, `outras-telas.md` (formulário, estoque, compras,
fechamento, manutenção, menu) e `syncs.md`.

## Como falar comigo (Raissa)
- Sou especialista em suprimentos, **não sou programadora**. Explique em português simples.
- Economize créditos: respostas diretas, sem rodeios.
- **Nunca** altere ou apague dados sem me mostrar antes e eu dizer "pode".
- Sempre que mudar algo no banco, me dê também o SQL de **desfazer**.

## O sistema
Páginas HTML + JavaScript puro, hospedadas no **Vercel**, com banco **Supabase**
(projeto `eugefrjckrxisfpizkjb`). Dados do Protheus chegam por scripts **Python** que rodam no
meu computador (`C:\painel-protheus`) usando a chave `service_role`.

| Página | Para quê | Login |
|---|---|---|
| `index.html` | Painel master: solicitações, acompanhamento, mobilização, consolidados, Visão Gerentes, configurações | Sim (admin / somente visualização pela tabela `perfis_usuario`) |
| `gerente.html` | Link dos gerentes: avaliar solicitações dos seus CCs | Sim |
| `formulario.html` | Almoxarife pede material | Não |
| `estoque.html`, `compras.html` | Painéis de consulta | Não |
| `fechamento.html` (+ `login_fechamento.html`) | Fechamento de consumo | Sim |
| `manutencao.html` | Manutenção de veículos — **outro projeto Supabase** | Não |

## Como trabalhamos (fluxo seguro)
1. Mudança de código vai no branch de trabalho do chat (ex.: `claude/kind-ptolemy-v4icku`) → abre PR no GitHub.
2. O Vercel gera um **Preview** do PR. Eu testo lá.
3. Só com meu **"pode"** faz o Merge no `main` (site oficial).
4. **Depois do Merge, confira no GitHub se os commits realmente entraram no `main`.**
   (Já aconteceu de um PR ter sido publicado antes de receber as últimas mudanças.)
5. Teste no navegador headless (Playwright/Chromium) antes de enviar, com dados de exemplo.

**Atenção:** o Preview usa o **mesmo banco** do site oficial — só o código é separado.

**Atenção 2:** comandos que criam tabela / ligam RLS **travam pelo conector Supabase** (timeout de
60s). Para esses, me passe o SQL para eu rodar no **SQL Editor**.

## Mudanças já feitas no banco
| O quê | Detalhe | Desfazer |
|---|---|---|
| Funções `truncate_*`, `trocar_consumo_mensal`, `congelar_mes_anterior` | Só `service_role` pode executar (antes qualquer um) | `grant execute ... to anon, authenticated` |
| Limpeza de texto (anti-XSS) | Gatilhos `limpar_texto` em `solicitacoes` e `solicitacao_itens` trocam `< > "` por `‹ › ”` (descrição: só `< >`) | `drop trigger limpar_texto on ...` |
| `pedidos_redefinicao` | Constraint `email_valido` | `drop constraint email_valido` |
| `gerentes_cc` | Unique `(email, cc)` | `drop constraint gerentes_cc_email_cc_key` |
| `solicitacao_itens` | Colunas `qtd_gerente`, `master_alterado_por`, `master_alterado_em` | — |
| `solicitacoes` | Coluna `grupo_envio` (junta cards: ALAGOINHAS / RIBEIRA-DO-POMBAL / PAULO-AFONSO-2026-10) | `update ... set grupo_envio=null` |
| `rascunhos_gerente` | Rascunho do gerente no servidor, com RLS (cada um vê o seu) | `drop table` |
| `criar_solicitacao` | O **banco** grava a posição de estoque da filial e a data no envio (não confia no formulário) | versão antiga no histórico do chat |
| `ultimo_preco_compra(text[])` | Último preço de compra (pedido mais recente, ignora rejeitados) | `drop function` |
| Índices | `idx_sol_itens_solicitacao`, `idx_consumo_mensal_cc` | `drop index` |
| Índices da compras | `idx_scs_emissao`, `idx_pedidos_emissao` foram **removidos** (pesavam nos syncs) | — |
| RLS fase A | 19 tabelas do Protheus: leitura pública, escrita só `service_role` (estoque_sb2, consumo_*, mov_*, movimentos_entrada, pedidos_compra, sc_pedidos, sc_pedidos_v2, scs, pedidos, filiais, sync_log, aprovadores_pcs) | `alter table ... disable row level security` |
| `solicitacoes.atualizado_por` | E-mail de quem atualizou por último (gerente ou master); aparece no card "↻ atualizado dd/mm hh:mm · nome" (26/10) | `alter table public.solicitacoes drop column atualizado_por` |
| `justificativas_consumo` | RLS ligado (26/10): só `authenticated` lê/insere/altera; coluna `atualizado_por` | `alter table ... disable row level security` + `drop policy` + `drop column atualizado_por` |
| `pedidos_grupo` | Valor por pedido × grupo pelo status de cada item (Comparativo Mensal). RLS: leitura pública, escrita só `service_role`. Alimentada por `sync_pedidos_grupo` no `upload_compras.py` (23/10) | `drop table public.pedidos_grupo` |
| Solicitação nº 655 | Lançada a pedido da Raissa a partir da planilha de Baturité (Kauan, CC 141080101, 107 itens) | `delete` em `solicitacao_itens` e `solicitacoes` id 655 |
| `mobilizacoes.criado_em` | **Ainda sem default** — rodar `alter table public.mobilizacoes alter column criado_em set default now();` | — |

### Backups guardados
`backup_mobilizacoes_2026_10_22`, `backup_mobilizacao_itens_2026_10_22`, `backup_mobilizacao_scs_2026_10_22`
(mobilizações #31–35) e `backup_mob_36_37_*` (mobilizações de teste #36 e #37).

## Syncs alterados no computador da Raissa (26/10)
- `upload_compras.py`: grava `pedidos_grupo` (valor por pedido × grupo pelo status de cada item) e corrige
  `scs.pedido_preco/pedido_total` (antes ×10). Backup: `upload_compras_BACKUP.py`.
- `sync_movmult.py` (devoluções `mov_sd3_001`): só regrava mês atual/anterior não congelado — meses em
  `meses_congelados` ficam fixos (igual ao `sync_consumo_scp.py`). Backup: `sync_movmult_BACKUP.py`.
- Congelamento: `sync_consumo_scp.py` chama `congelar_mes_anterior` no 1º sync dos dias 1–5 do mês.

## Bibliotecas
- Supabase JS servido pelo próprio site: `vendor/supabase-2.118.0.js` (o jsdelivr falhou em 26/10).
  Não voltar a usar `cdn.jsdelivr.net`.

## Pendências (em ordem sugerida)
0. **Vida útil e próxima troca (combinado em 26/10, começar no próximo chat)**: a tabela `entregas_almoxarife`
   tem entregas por matrícula (só desde 03/08/2026). Pedir à Raissa o `sync_entregas.py` para trazer desde 2025;
   calcular vida útil por item (mediana entre trocas da mesma pessoa, motivos 3/4/9) + vida útil padrão cadastrável;
   próxima troca por pessoa; trocas previstas 90 dias por filial×item alimentando o painel de ruptura; trocas vencidas.
   Teste: luva de vaqueta 17 dias, luva de cobertura 35 dias. Outros pontos combinados p/ ruptura: mínimo por equipe
   p/ itens críticos (NR-10/altura), reserva de mobilização, grade de fardamento semestral, alerta de formulário não enviado.
1. **Segurança RLS fase B**: configurações (centros_custo, gerentes_cc, cc_grupos, itens, cc_pessoas, bases_status…) — todos leem, só admin altera (função `is_admin()` usando `perfis_usuario`).
2. **Segurança RLS fase C**: `solicitacoes` e `solicitacao_itens` (formulário cria via RPC; gerente altera os CCs dele; admin tudo). Também `perfis_usuario` e `pedidos_redefinicao`.
3. **Syncs** (ver `docs/syncs.md`): rodar em fila, não todos juntos; parar syncs que não alimentam o site.
4. **Tela compras**: reaplicar carga por período (commits `f849d5d` e `8137792`) quando os syncs estiverem leves, recriando os índices.
5. **Tela estoque**: otimizar (baixa estoque inteiro e 38 mil itens no comparativo).
6. **Recuperação de senha** do gerente não funciona (a senha temporária fica na tabela e nada a aplica).
7. Investigar: gerente **max@** dizendo ver coisas da Amanda (banco está certo — provável login de outra pessoa no navegador).
8. E-mail suspeito em `gerentes_cc`: `moslaynunes@bq.com.br` (falta o "e" de beq?).
9. Custo médio do Protheus distorcido em ~3% dos itens (avisar quem cuida do Protheus).
