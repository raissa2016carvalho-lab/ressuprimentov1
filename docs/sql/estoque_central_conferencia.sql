-- Conferência: itens atendidos pelo estoque central, com o preço usado no Painel
-- Preço = custo médio da filial (estoque_sb2); sem custo na filial → custo de outra filial;
-- se o custo estiver 5x acima/abaixo do preço do cadastro (itens.preco) ou não existir → preço do cadastro.
with base as (
  select s.id sol, trim(s.filial) filial, c.nome base, trim(i.codigo) codigo, i.descricao, i.qtd_estoque_central qtd, i.quantidade fica_para_sc
  from solicitacao_itens i join solicitacoes s on s.id=i.solicitacao_id left join centros_custo c on c.cc::text=s.cc::text
  where i.qtd_estoque_central > 0),
cf as (select distinct on (trim(filial), trim(codigo)) trim(filial) filial, trim(codigo) codigo, custo_medio
       from estoque_sb2 where custo_medio > 0 order by trim(filial), trim(codigo), id),
qq as (select distinct on (trim(codigo)) trim(codigo) codigo, custo_medio from estoque_sb2 where custo_medio > 0 order by trim(codigo), id),
pr as (select trim(codigo) codigo, preco from itens where preco > 0),
y as (select b.*, cf.custo_medio c_fil, qq.custo_medio c_outra, pr.preco, coalesce(cf.custo_medio,qq.custo_medio) c0 from base b
      left join cf on cf.filial=b.filial and cf.codigo=b.codigo left join qq on qq.codigo=b.codigo left join pr on pr.codigo=b.codigo),
z as (select y.*,
        case when c0 is not null and (preco is null or c0 between preco/5 and preco*5) then c0 else preco end custo,
        case when c0 is not null and (preco is null or c0 between preco/5 and preco*5)
             then case when c_fil is not null then 'custo médio da filial' else 'custo médio de outra filial' end
             when preco is not null then 'preço do cadastro' else 'SEM PREÇO' end origem
      from y)
select sol as "Solicitação", filial as "Filial", base as "Base", codigo as "Código", descricao as "Descrição",
       qtd as "Qtd estoque central", round(custo,2) as "Custo unitário", origem as "Origem do preço",
       round(qtd*custo,2) as "Valor", fica_para_sc as "Fica para a SC"
from z
order by qtd*custo desc nulls last;
