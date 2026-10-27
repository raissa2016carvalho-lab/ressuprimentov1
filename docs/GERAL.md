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
| Vida útil e trocas (26/10) | Função `familia_item(texto)` (junta tamanhos: tira "Nº 42", "TAM M", "- G"); visões materializadas `mv_vida_util` (vida útil por item = mediana entre trocas da mesma pessoa, motivos 3/4/9) e `mv_trocas_pessoa` (última entrega e próxima troca por matrícula × item pessoal); visão `vw_trocas_pessoa` (só pessoas ativas e sem atraso maior que 1 vida útil); função `trocas_previstas(dias_epi, dias_fard)` (usada no painel de ruptura); `atualizar_vida_util()` (recalcula; só `service_role`) | `drop function trocas_previstas(int,int), atualizar_vida_util(); drop view vw_trocas_pessoa; drop materialized view mv_trocas_pessoa, mv_vida_util; drop function familia_item(text);` |
| `consumo_por_motivo(mes_ini, motivos[])` (27/10) | Soma do `consumo_scp` por filial × produto × mês × motivo (o ruptura usa para tirar MOBILIZAÇÃO/ADMISSIONAL do consumo). Só leitura | `drop function consumo_por_motivo(text,text[]);` |
| `estoque_seguranca` (27/10, **Raissa roda no SQL Editor**) | Itens marcados no `ruptura.html` (🛡️): filial, código, descrição, qtd de segurança, observação. RLS: leitura e gravação pela página (sem login) | `drop table public.estoque_seguranca;` |
| `incluir_item_ruptura(solicitacao_id, codigo, qtd)` (27/10) | Botão "➕ Incluir/Ajustar no formulário" do ruptura. Só formulário sem SC e status pendente/aguardando_master; inclui (almoxarife **vazio** — com 0 o card do Painel principal esconde o item —, sugestão 0) ou ajusta a final; item fica **aprovado**, `master_alterado_por = 'painel ruptura'`. Testada com transação desfeita | `drop function incluir_item_ruptura(bigint,text,numeric);` |
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
0. **Painel Risco de Ruptura v2 — publicado em 27/10 (PR #28, que inclui o #27)**. Falta: rodar o SQL da `estoque_seguranca` (ver `outras-telas.md`). **Vida útil e trocas — FEITO em 26/10**: aba "Vida útil e trocas" no `ruptura.html` e trocas previstas
   entrando na meta do ruptura. **Falta**: (a) o recálculo — a vida útil e as próximas trocas ficam paradas na foto de 26/10 até rodar
   `atualizar_vida_util()`. Opção 1: no fim do `sync_entregas.py` acrescentar `supabase.rpc('atualizar_vida_util').execute()`.
   Opção 2: ligar o agendador do banco (SQL Editor): `create extension if not exists pg_cron;` e
   `select cron.schedule('vida_util','30 9 * * *','select public.atualizar_vida_util()');` (06:30 de Brasília; desfazer: `select cron.unschedule('vida_util');`).
   (b) vida útil padrão cadastrável (tabela para a Raissa corrigir a vida útil de um item à mão). (c) lista de itens pessoais é por palavra
   (fardamento inteiro + LUVA, BOTA, TENIS, CALCA, CAMISA, OCULOS, BALACLAVA, PERNEIRA, CARNEIRA, CAPUZ, CAPACETE, CAPA DE CHUVA, MASCARA,
   PROTETOR SOLAR/LABIAL/AURICULAR/FACIAL, MANGA DE BORRACHA, KIT EPI cinto/talabarte/trava-quedas) — revisar com a Raissa.
   Anotações antigas desta pendência (combinado em 26/10): a tabela `entregas_almoxarife`
   tem entregas por matrícula (só desde 03/08/2026). Pedir à Raissa o `sync_entregas.py` para trazer desde 2025;
   calcular vida útil por item (mediana entre trocas da mesma pessoa, motivos 3/4/9) + vida útil padrão cadastrável;
   próxima troca por pessoa; trocas previstas 90 dias por filial×item alimentando o painel de ruptura; trocas vencidas.
   **Histórico carregado em 26/10** (`sync_entregas.py --desde 20250101`): 219.577 entregas, jan/2025–out/2026, 5.521 pessoas.
   Vida útil (mediana, motivos 3/4/9): luva vaqueta 23 d; luva cobertura 74 d; óculos fumê 118 d; balaclava 148 d;
   calça/camisa retardante ENEL ~95 d; bota NR10 ~180 d; perneira 204 d. 209 itens EPI/fardamento com ≥20 trocas.
   Pessoas ativas (entrega nos últimos 60 d): 2.007 → 3.537 trocas previstas em 30 d, 10.156 em 90 d; 10.560 "vencidas"
   (precisa filtrar só itens pessoais — tinta, lâmina etc. não são por pessoa; e agrupar tamanhos do fardamento). Outros pontos combinados p/ ruptura: mínimo por equipe
   p/ itens críticos (NR-10/altura), reserva de mobilização, grade de fardamento semestral, alerta de formulário não enviado.
0b. **Ruptura — "a caminho" sem olhar status da SC (achado em 27/10, fazer depois)**: o "a caminho" vem do `estoque_sb2.saldo_pedido`
   (Protheus), que não sabe se a SC foi rejeitada ou o PC está em aprovação. Dos 1.747 filial×item de EPI/fard com saldo a caminho:
   541 têm PC válido em `sc_pedidos_v2`, 102 só "Em aprovação", **1.205 sem nenhum PC aberto** na base. Proposta: "a caminho" = só PCs
   válidos (Pendente / Recebido parcialmente / Em recebimento, SC não rejeitada nem eliminada); "Em aprovação" mostrado à parte e sem
   cobrir a falta; aviso quando o SB2 tem saldo sem PC válido.
1. **Segurança RLS fase B**: configurações (centros_custo, gerentes_cc, cc_grupos, itens, cc_pessoas, bases_status…) — todos leem, só admin altera (função `is_admin()` usando `perfis_usuario`).
2. **Segurança RLS fase C**: `solicitacoes` e `solicitacao_itens` (⚠ o `ruptura.html` lê essas tabelas para a auditoria do último formulário — manter leitura ou fazer função) (formulário cria via RPC; gerente altera os CCs dele; admin tudo). Também `perfis_usuario` e `pedidos_redefinicao`.
3. **Syncs** (ver `docs/syncs.md`): rodar em fila, não todos juntos; parar syncs que não alimentam o site.
4. **Tela compras**: reaplicar carga por período (commits `f849d5d` e `8137792`) quando os syncs estiverem leves, recriando os índices.
5. **Tela estoque**: otimizar (baixa estoque inteiro e 38 mil itens no comparativo).
6. **Recuperação de senha** do gerente não funciona (a senha temporária fica na tabela e nada a aplica).
7. Investigar: gerente **max@** dizendo ver coisas da Amanda (banco está certo — provável login de outra pessoa no navegador).
8. E-mail suspeito em `gerentes_cc`: `moslaynunes@bq.com.br` (falta o "e" de beq?).
9. Custo médio do Protheus distorcido em ~3% dos itens (avisar quem cuida do Protheus).
