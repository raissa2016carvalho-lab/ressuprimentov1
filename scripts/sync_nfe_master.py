"""
sync_nfe_master.py — copia as NF-e do NFe Master (HMIT) para o Supabase (tabela nfe_master).

Roda no computador da Raissa (o banco do NFe Master está na rede interna: 192.168.1.13).
- 1ª vez: carrega as notas emitidas desde DESDE.
- Depois: só as notas incluídas/alteradas nos últimos 3 dias (upsert pelo id; nunca apaga a tabela).

Uso:
  python sync_nfe_master.py              -> roda uma vez
  python sync_nfe_master.py --loop       -> roda a cada 30 minutos
  python sync_nfe_master.py --desde 20250101   -> recarrega a partir dessa data
Precisa: pip install psycopg2-binary supabase
"""
import sys, time, datetime, decimal
import psycopg2, psycopg2.extras
from supabase import create_client

# ── NFE MASTER (PostgreSQL) — login do banco nfemaster ─────────────────────────────
SERVIDOR = "192.168.1.13"
PORTA    = 5432
USUARIO  = "XXXX"
SENHA    = r"XXXX"
BANCO    = "nfemaster"

# ── SUPABASE — o mesmo dos outros syncs ────────────────────────────────────────────
RESSUP_URL = "https://eugefrjckrxisfpizkjb.supabase.co"
RESSUP_KEY = "XXXX"

NFE = dict(host=SERVIDOR, port=PORTA, dbname=BANCO, user=USUARIO, password=SENHA)
SUPABASE_URL, SUPABASE_KEY = RESSUP_URL, RESSUP_KEY
DESDE = "20250101"               # 1ª carga: notas emitidas a partir desta data
DIAS_REVISAO = 3                 # nas próximas vezes, revisa o que mudou nestes dias
LOTE = 500

SQL = """
select n.id,
       n.chaveacesso                                   as chave,
       n.numeronota                                    as numero,
       n.numeroserie                                   as serie,
       n.modelodocumento                               as modelo,
       right(split_part(split_part(e.cnpj,'/',2),'-',1), 2) as filial,
       e.nomefantasia                                  as empresa_nome,
       e.cnpj                                          as empresa_cnpj,
       coalesce(n.cnpjemissor, n.cpfemissor)           as fornecedor_cnpj,
       n.razaosocialemissor                            as fornecedor_nome,
       n.nomefantasiaemissor                           as fornecedor_fantasia,
       n.ufemissor                                     as fornecedor_uf,
       p.codigofornecedor                              as fornecedor_cod,
       p.lojafornecedor                                as fornecedor_loja,
       n.dataemissao                                   as emissao,
       n.dataautorizacao                               as autorizacao,
       n.datainclusao                                  as chegada,
       n.dataintegracao                                as integracao,
       greatest(n.dataalteracao, n.datainclusao, p.dataalteracao, p.datainclusao) as alterado,
       n.statusnfe                                     as status_nfe,
       n.statusintegracao                              as status_integracao,
       p.statusintegracaoprotheus                      as status_protheus,
       p.msgretornointegracao                          as msg_protheus,
       p.pedido                                        as pedido,
       n.tipooperacao                                  as tipo_operacao,
       n.descnatop                                     as natureza,
       n.valortotalnota                                as valor_total,
       n.valortotalprodutos                            as valor_produtos,
       n.flagemtratativa                               as em_tratativa,
       n.motivoemtratativa                             as motivo_tratativa,
       n.dataemtratativa                               as data_tratativa,
       n.logerrointegracaoerp                          as erro_integracao,
       n.ultimoeventomanifestacao                      as manifestacao,
       n.dataultimoeventomanifestacao                  as data_manifestacao
from nfemanager.tb_nfe n
left join nfemanager.tb_empresanfe e on e.id = n.idempresa
left join (
  select distinct on (idnfe) * from protheus.tb_integracaoprotheusnfe order by idnfe, id desc
) p on p.idnfe = n.id
where {filtro}
order by n.id
"""

# Itens das notas (mesmo filtro das notas) + o que o NFe Master associou do Protheus (pedido, produto, CC)
SQL_ITENS = """
select i.id,
       i.idnfe                 as nfe_id,
       i.numeroitem            as item,
       i.codigoproduto         as codigo_forn,
       i.descricaoproduto      as descricao,
       i.ncm, i.cfop,
       i.unidadecomercial      as unidade,
       i.quantidadecomercial   as quantidade,
       i.valorunitario         as valor_unit,
       i.valortotal            as valor_total,
       i.numeropedido          as pedido_xml,
       i.numeroitempedido      as item_pedido_xml,
       ip.codprodutoprotheus   as cod_protheus,
       ip.descprodutoprotheus  as desc_protheus,
       ip.idpedidocompra       as pc,
       ip.iditempedidocompra   as item_pc,
       ip.centrodecusto        as cc,
       ip.qtdassociada         as qtd_associada
from nfemanager.tb_nfeitem i
join nfemanager.tb_nfe n on n.id = i.idnfe
left join (
  select distinct on (idnfe) * from protheus.tb_integracaoprotheusnfe order by idnfe, id desc
) p on p.idnfe = n.id
left join (
  select distinct on (idnfeitem) * from protheus.tb_integracaoprotheusnfeitem order by idnfeitem, id desc
) pi on pi.idnfeitem = i.id
left join (
  select distinct on (idintegracaoprotheusnfeitem) * from protheus.tb_integracaoprotheusitempedido
  order by idintegracaoprotheusnfeitem, id desc
) ip on ip.idintegracaoprotheusnfeitem = pi.id
where {filtro}
order by i.id
"""


def _enviar(sb, con, tabela, sql, nome):
    cur = con.cursor(name="sync_" + tabela, cursor_factory=psycopg2.extras.RealDictCursor)
    cur.itersize = LOTE
    cur.execute(sql)
    total = 0
    while True:
        linhas = cur.fetchmany(LOTE)
        if not linhas:
            break
        dados = [{k: _json(v) for k, v in l.items()} for l in linhas]
        for tentativa in range(4):
            try:
                sb.table(tabela).upsert(dados, on_conflict="id").execute()
                break
            except Exception as e:
                print("  erro no lote, tentando de novo:", e)
                time.sleep(5 * (tentativa + 1))
        else:
            raise SystemExit("Não consegui gravar no Supabase. Parei para não deixar a tabela pela metade.")
        total += len(dados)
        print(f"  {total} {nome} enviados ao Supabase...", flush=True)
    cur.close()
    return total


def _json(v):
    if isinstance(v, (datetime.datetime, datetime.date)):
        return v.isoformat()
    if isinstance(v, decimal.Decimal):
        return float(v)
    return v


def rodar(desde=None):
    sb = create_client(SUPABASE_URL, SUPABASE_KEY)
    ultimo = None
    if not desde:
        r = sb.table("sync_log").select("atualizado_em").eq("chave", "nfe_master").execute()
        ultimo = r.data[0]["atualizado_em"] if r.data else None
    if ultimo:
        filtro = ("greatest(n.dataalteracao, n.datainclusao, p.dataalteracao, p.datainclusao) "
                  f">= now() - interval '{DIAS_REVISAO} days'")
    else:
        d = desde or DESDE
        filtro = f"n.dataemissao >= '{d[:4]}-{d[4:6]}-{d[6:8]}'"

    inicio = time.time()
    print("Conectando no NFe Master...", flush=True)
    con = psycopg2.connect(connect_timeout=20, **NFE)
    con.set_session(readonly=True)          # só leitura no NFe Master
    print("Conectado. Buscando as notas (" + ("revisão dos últimos dias" if ultimo else "carga completa") + ")...", flush=True)
    total = _enviar(sb, con, "nfe_master", SQL.format(filtro=filtro), "notas")
    print("Agora os itens das notas...", flush=True)
    itens = _enviar(sb, con, "nfe_master_itens", SQL_ITENS.format(filtro=filtro), "itens")
    con.close()
    # atualiza o cruzamento NF × SD1 usado pela tela (tabela pronta, para a tela abrir rápido)
    try:
        sb.rpc("atualizar_nfe_sd1").execute()
        print("Cruzamento com a SD1 atualizado.", flush=True)
    except Exception as e:
        print("  (não consegui atualizar o cruzamento com a SD1:", e, ")", flush=True)
    sb.table("sync_log").upsert({"chave": "nfe_master", "atualizado_em": datetime.datetime.now().isoformat(),
                                 "total": total}, on_conflict="chave").execute()
    print(f"OK: {total} notas e {itens} itens em {time.time() - inicio:.0f}s ({'revisão' if ultimo else 'carga completa'})")


if __name__ == "__main__":
    desde = sys.argv[sys.argv.index("--desde") + 1] if "--desde" in sys.argv else None
    if "--loop" in sys.argv:
        while True:
            try:
                rodar(desde)
            except Exception as e:
                print("ERRO:", e)
            desde = None
            time.sleep(30 * 60)
    else:
        rodar(desde)
