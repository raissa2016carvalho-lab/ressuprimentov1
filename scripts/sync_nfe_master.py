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
       n.dataultimoeventomanifestacao                  as data_manifestacao,
       pr.prenota                                      as prenota,
       substring(encode(x.xmlnota,'escape') from '<infCpl>(.*?)</infCpl>')         as rodape,
       substring(encode(x.xmlnota,'escape') from '<infAdFisco>(.*?)</infAdFisco>') as rodape_fisco,
       substring(encode(x.xmlnota,'escape') from '<xPed>(.*?)</xPed>')             as xped
from nfemanager.tb_nfe n
left join nfemanager.tb_nfexml x on x.id = n.id      -- XML da nota (mesmo id da nota)
left join nfemanager.tb_empresanfe e on e.id = n.idempresa
left join (
  select distinct on (idnfe) * from protheus.tb_integracaoprotheusnfe order by idnfe, id desc
) p on p.idnfe = n.id
-- pré-nota: 1ª vez que o NFe Master criou a pré-nota no Protheus com sucesso (log INCLUIPRENOTA)
left join lateral (
  select min(m.datainclusao) as prenota
  from protheus.tb_integracaoprotheusnfe i
  join protheus.tb_retornointegracaoprotheusnfe r on r.idintegracaoprotheusnfe = i.id
  join protheus.tb_mensagemretornointegracaoprotheusnfe m on m.idretornointegracaoprotheusnfe = r.id
  where i.idnfe = n.id and m.mensagem ilike 'Integração realizada com sucesso%'
) pr on true
where ({filtro}){extra}
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

# Notas de SERVIÇO (NFS-e, esquema nfse do NFe Master) — entram na MESMA tabela do painel (nfe_master),
# com id negativo (para não colidir com as NF-e) e modelo 'NFSE'.
SQL_NFSE = """
select -n.id                                           as id,
       n.chaveacesso                                   as chave,
       case when n.nrnfse::text ~ '^[0-9]+$' then n.nrnfse::text::bigint end as numero,
       null::bigint                                    as serie,
       'NFSE'                                          as modelo,
       right(split_part(split_part(e.cnpj,'/',2),'-',1), 2) as filial,
       e.nomefantasia                                  as empresa_nome,
       e.cnpj                                          as empresa_cnpj,
       n.nrcnpjprestador                               as fornecedor_cnpj,
       n.dsrazaosocialprestador                        as fornecedor_nome,
       n.dsnomefantasiaprestador                       as fornecedor_fantasia,
       n.cdufprestador::text                           as fornecedor_uf,
       n.dtemissaonfse                                 as emissao,
       n.datainclusao                                  as chegada,
       n.dataintegracao                                as integracao,
       greatest(n.dataalteracao, n.datainclusao)       as alterado,
       case when n.dtcancelamento is not null then 'C' else 'A' end as status_nfe,
       n.statusintegracao::text                        as status_integracao,
       n.numeropedido::text                            as pedido,
       'SERVICO'                                       as tipo_operacao,
       left(n.dsdiscriminacao, 300)                    as natureza,
       n.vlservico                                     as valor_total,
       n.vlliquidonfse                                 as valor_produtos,
       n.flagemtratativa                               as em_tratativa,
       n.motivoemtratativa                             as motivo_tratativa,
       n.dataemtratativa                               as data_tratativa,
       n.ultimoeventomanifestacao::text                as manifestacao,
       n.dataultimoeventomanifestacao                  as data_manifestacao,
       n.dsoutrasinfo                                  as rodape,
       n.numeropedido::text                            as xped
from nfse.tb_nfse n
left join nfemanager.tb_empresanfe e on e.id = n.idempresa
where {filtro}
order by n.id
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
        dados = [_ajusta({k: _json(v) for k, v in l.items()}) for l in linhas]
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


import re, html

def _desescapa(t):
    # texto vindo de encode(bytea,'escape'): bytes fora do ASCII viram \ooo e a barra vira \\
    if not t:
        return None
    out, i = bytearray(), 0
    while i < len(t):
        if t[i] == '\\' and t[i+1:i+4].isdigit() and len(t[i+1:i+4]) == 3:
            out.append(int(t[i+1:i+4], 8)); i += 4
        elif t[i] == '\\' and t[i+1:i+2] == '\\':
            out.append(92); i += 2
        else:
            out.extend(t[i].encode('latin-1', 'replace')); i += 1
    txt = out.decode('utf-8', 'replace')
    return html.unescape(txt).strip() or None

# "pedido do cliente" escrito no rodapé (é o nosso nº de pedido de compra)
# Fica o número que EXISTE nos nossos pedidos (PEDIDOS_VALIDOS, lido do Supabase no começo da rodada);
# se nenhum existir, só aceita frase bem clara ("pedido do cliente", "pedido de compra").
PEDIDOS_VALIDOS = set()
_RE_GERAL = re.compile(r'(?:pedido|ped\.?|p\.?c\.?|o\.?c\.?)\D{0,12}?(\d{4,7})\b', re.I)
_RE_PED = [re.compile(p, re.I) for p in (
    r'pedido\s+d[oe]\s+cliente\D{0,15}?(\d{4,10})',
    r'pedido\s+de\s+compras?\D{0,15}?(\d{4,10})',
    r'\bP\.?\s?C\.?\s*(?:n[ºo°.]*)?\s*[:\-]?\s*(\d{5,10})',
    r'\bO\.?\s?C\.?\s*(?:n[ºo°.]*)?\s*[:\-]\s*(\d{4,10})',
    r'seu\s+pedido\D{0,15}?(\d{4,10})',
)]

def _norm6(v):
    v = re.sub(r'\D', '', v or '')
    return (v.zfill(6) if len(v) < 6 else v) if 4 <= len(v) <= 10 else None

def _pedido_cliente(xped, rodape):
    fortes = [m.group(1) for rx in _RE_PED for m in rx.finditer(rodape or '')]
    cands = [_norm6(xped)] + [_norm6(v) for v in fortes] + [_norm6(m.group(1)) for m in _RE_GERAL.finditer(rodape or '')]
    cands = [c for c in cands if c]
    if PEDIDOS_VALIDOS:
        for c in cands:
            if c in PEDIDOS_VALIDOS:
                return c
    # nenhum confere com os pedidos: só a frase clara do rodapé (o xPed sozinho pode ser outra coisa)
    return _norm6(fortes[0]) if fortes else None

def _ajusta(d):
    # rodapé, rodapé do fisco e pedido do cliente (só nas tabelas de notas)
    if 'xped' in d:
        for k in ('rodape', 'rodape_fisco'):
            if k in d:
                d[k] = _desescapa(d[k]) if k == 'rodape_fisco' or d.get('modelo') != 'NFSE' else (d[k] or None)
        xp = d.pop('xped')
        xp = _desescapa(xp) if d.get('modelo') != 'NFSE' else xp
        d['pedido_cliente'] = _pedido_cliente(xp, d.get('rodape'))
    return d


def _json(v):
    if isinstance(v, (datetime.datetime, datetime.date)):
        return v.isoformat()
    if isinstance(v, decimal.Decimal):
        return float(v)
    return v


def _carregar_pedidos(sb):
    # números de pedido de compra que existem (tabela pedidos do painel de Compras)
    global PEDIDOS_VALIDOS
    nums, ini = set(), 0
    try:
        while True:
            r = sb.table("pedidos").select("C7_NUM").range(ini, ini + 999).execute()
            for l in r.data or []:
                v = re.sub(r'\D', '', str(l.get("C7_NUM") or ''))
                if v:
                    nums.add(v.zfill(6))
            if not r.data or len(r.data) < 1000:
                break
            ini += 1000
    except Exception as e:
        print("  (não consegui ler a lista de pedidos para conferir o pedido do cliente:", e, ")", flush=True)
    PEDIDOS_VALIDOS = nums
    print(f"  {len(nums)} números de pedido para conferir o pedido do cliente.", flush=True)


def rodar(desde=None):
    sb = create_client(SUPABASE_URL, SUPABASE_KEY)
    _carregar_pedidos(sb)
    ultimo = None
    if not desde:
        r = sb.table("sync_log").select("atualizado_em").eq("chave", "nfe_master").execute()
        ultimo = r.data[0]["atualizado_em"] if r.data else None
    extra = ""
    if ultimo:
        filtro = ("greatest(n.dataalteracao, n.datainclusao, p.dataalteracao, p.datainclusao) "
                  f">= now() - interval '{DIAS_REVISAO} days'")
        # nota que ganhou pré-nota nos últimos dias também volta (a pré-nota não muda a data de alteração)
        extra = f" or pr.prenota >= now() - interval '{DIAS_REVISAO} days'"
    else:
        d = desde or DESDE
        filtro = f"n.dataemissao >= '{d[:4]}-{d[4:6]}-{d[6:8]}'"

    inicio = time.time()
    print("Conectando no NFe Master...", flush=True)
    con = psycopg2.connect(connect_timeout=20, **NFE)
    con.set_session(readonly=True)          # só leitura no NFe Master
    print("Conectado. Buscando as notas (" + ("revisão dos últimos dias" if ultimo else "carga completa") + ")...", flush=True)
    total = _enviar(sb, con, "nfe_master", SQL.format(filtro=filtro, extra=extra), "notas")
    print("Agora os itens das notas...", flush=True)
    itens = _enviar(sb, con, "nfe_master_itens", SQL_ITENS.format(filtro=filtro), "itens")
    # notas de serviço (NFS-e): mesmo período, pelas datas da própria NFS-e
    print("Agora as notas de serviço (NFS-e)...", flush=True)
    filtro_nfse = (f"greatest(n.dataalteracao, n.datainclusao) >= now() - interval '{DIAS_REVISAO} days'" if ultimo
                   else f"n.dtemissaonfse >= '{(desde or DESDE)[:4]}-{(desde or DESDE)[4:6]}-{(desde or DESDE)[6:8]}'")
    try:
        nfse = _enviar(sb, con, "nfe_master", SQL_NFSE.format(filtro=filtro_nfse), "notas de serviço")
    except Exception as e:
        nfse = 0
        con.rollback()
        print("  (não consegui trazer as NFS-e:", e, ")", flush=True)
    con.close()
    # atualiza o cruzamento NF × SD1 usado pela tela (tabela pronta, para a tela abrir rápido)
    try:
        sb.rpc("atualizar_nfe_sd1").execute()
        print("Cruzamento com a SD1 atualizado.", flush=True)
    except Exception as e:
        print("  (não consegui atualizar o cruzamento com a SD1:", e, ")", flush=True)
    sb.table("sync_log").upsert({"chave": "nfe_master", "atualizado_em": datetime.datetime.now().isoformat(),
                                 "total": total}, on_conflict="chave").execute()
    print(f"OK: {total} notas, {itens} itens e {nfse} notas de serviço em {time.time() - inicio:.0f}s ({'revisão' if ultimo else 'carga completa'})")


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
        # rodando com dois cliques: a janela espera o Enter para dar tempo de ler o resultado ou o erro
        try:
            rodar(desde)
        except BaseException as e:
            import traceback
            print("\n❌ ERRO:", e)
            traceback.print_exc()
        input("\nPressione Enter para fechar...")
