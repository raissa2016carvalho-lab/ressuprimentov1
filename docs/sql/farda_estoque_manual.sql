-- Contagem manual de estoque de fardamento (18/11/2026)
-- farda_estoque_manual: a quantidade contada substitui o saldo do SB2 naquele armazém
-- (armazem '*' = todos os armazéns da filial). Os outros armazéns continuam pelo SB2.
-- farda_compra devolve 'estoque' já com a contagem e 'estoque_manual' (para o ✎ na tela).
-- 1ª carga: inventário da Matriz (filial 01), 15 itens ENEL, contado em 18/11/2026.
-- Em 19/11/2026 passou a valer para TODOS os armazéns da Matriz (armazem = '*'): o SB2 da Matriz
-- desses itens (inclusive armazéns 0011 e 10) é ignorado e vale só a contagem. Itens não contados seguem pelo SB2.
--
-- Lançar / corrigir uma contagem:
--   insert into farda_estoque_manual (filial, codigo, armazem, qtd, contado_em, obs)
--   values ('01','100000377','01',0,current_date,'inventário')
--   on conflict (filial, codigo, armazem) do update set qtd = excluded.qtd, contado_em = excluded.contado_em, obs = excluded.obs;
-- Voltar a usar o SB2 de um item:   delete from farda_estoque_manual where filial = '01' and codigo = '100000377';
-- Voltar a usar o SB2 em tudo:      delete from farda_estoque_manual;
-- Desfazer de vez: drop table farda_estoque_manual e recriar farda_compra sem o not exists / union all e sem 'estoque_manual'.

create table if not exists farda_estoque_manual (
  filial    text not null,
  codigo    text not null,
  armazem   text not null default '01',
  qtd       numeric not null,
  contado_em date not null default current_date,
  obs       text,
  primary key (filial, codigo, armazem)
);
alter table farda_estoque_manual enable row level security;
revoke all on farda_estoque_manual from anon, authenticated;
