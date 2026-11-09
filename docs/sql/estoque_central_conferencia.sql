-- Conferência: itens atendidos pelo estoque central, com o preço usado no Painel
-- Preço = custo médio da filial (estoque_sb2; se ficar 5x acima/abaixo do cadastro, usa o cadastro);
-- sem custo na filial → preço do cadastro (itens.preco); sem cadastro → mediana do custo das outras filiais.
with base as (
  select s.id sol, trim(s.filial) filial, c.nome base, trim(i.codigo) codigo, i.descricao, i.qtd_estoque_central qtd, i.quantidade fica_para_sc
  from solicitacao_itens i join solicitacoes s on s.id=i.solicitacao_id left join centros_custo c on c.cc::text=s.cc::text
  where i.qtd_estoque_central > 0),
pr as (select trim(codigo) codigo, preco from itens where preco > 0),
cf as (select distinct on (trim(filial), trim(codigo)) trim(filial) filial, trim(codigo) codigo, custo_medio
       from estoque_sb2 where custo_medio > 0 order by trim(filial), trim(codigo), id),
cfs as (select cf.filial, cf.codigo, case when pr.preco is not null and (cf.custo_medio<pr.preco/5 or cf.custo_medio>pr.preco*5) then pr.preco else cf.custo_medio end c from cf left join pr using(codigo)),
med as (select codigo, percentile_cont(0.5) within group (order by c) c from cfs group by codigo),
z as (select b.*, coalesce(f.c, pr.preco, med.c) custo,
        case when f.c is not null then 'custo médio da filial' when pr.preco is not null then 'preço do cadastro'
             when med.c is not null then 'mediana das outras filiais' else 'SEM PREÇO' end origem
      from base b left join cfs f on f.filial=b.filial and f.codigo=b.codigo left join pr on pr.codigo=b.codigo left join med on med.codigo=b.codigo)
select sol as "Solicitação", filial as "Filial", base as "Base", codigo as "Código", descricao as "Descrição",
       qtd as "Qtd estoque central", round(custo,2) as "Custo unitário", origem as "Origem do preço",
       round(qtd*custo,2) as "Valor", fica_para_sc as "Fica para a SC"
from z
order by qtd*custo desc nulls last;
