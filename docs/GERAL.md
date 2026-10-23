# Ressuprimento B&Q — Visão geral (leia primeiro)

Atualizado em 23/10/2026. Este arquivo resume o sistema, as regras de trabalho e tudo o que já foi
mudado no banco. Os detalhes de cada tela estão nos outros arquivos desta pasta.

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
1. Mudança de código vai no branch `claude/kind-volta-7vg1nq` → abre PR no GitHub.
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
| `mobilizacoes.criado_em` | **Ainda sem default** — rodar `alter table public.mobilizacoes alter column criado_em set default now();` | — |

### Backups guardados
`backup_mobilizacoes_2026_10_22`, `backup_mobilizacao_itens_2026_10_22`, `backup_mobilizacao_scs_2026_10_22`
(mobilizações #31–35) e `backup_mob_36_37_*` (mobilizações de teste #36 e #37).

## Pendências (em ordem sugerida)
1. **Segurança RLS fase B**: configurações (centros_custo, gerentes_cc, cc_grupos, itens, cc_pessoas, bases_status…) — todos leem, só admin altera (função `is_admin()` usando `perfis_usuario`).
2. **Segurança RLS fase C**: `solicitacoes` e `solicitacao_itens` (formulário cria via RPC; gerente altera os CCs dele; admin tudo). Também `perfis_usuario` e `pedidos_redefinicao`.
3. **Syncs** (ver `docs/syncs.md`): rodar em fila, não todos juntos; parar syncs que não alimentam o site.
4. **Tela compras**: reaplicar carga por período (commits `f849d5d` e `8137792`) quando os syncs estiverem leves, recriando os índices.
5. **Tela estoque**: otimizar (baixa estoque inteiro e 38 mil itens no comparativo).
6. **Recuperação de senha** do gerente não funciona (a senha temporária fica na tabela e nada a aplica).
7. Investigar: gerente **max@** dizendo ver coisas da Amanda (banco está certo — provável login de outra pessoa no navegador).
8. E-mail suspeito em `gerentes_cc`: `moslaynunes@bq.com.br` (falta o "e" de beq?).
9. Custo médio do Protheus distorcido em ~3% dos itens (avisar quem cuida do Protheus).
