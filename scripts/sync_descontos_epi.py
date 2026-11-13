# -*- coding: utf-8 -*-
"""
sync_descontos_epi.py — Descontos de EPI (customização LWHZZA010) para o painel de abono/desconto.
Junta cada desconto com a SA (LWHSCP001: emissão, centro de custo, observação, solicitante) e com o
cadastro de funcionários (LWHSRA001: nome, CC e função) e grava na tabela descontos_epi do Supabase.
As decisões (abonar/descontar) ficam em outra tabela e NÃO são apagadas por este script.

Salvar em: C:\\painel-protheus\\sync_descontos_epi.py
1ª vez (carga completa):  py sync_descontos_epi.py --desde 20251221
Depois (dia a dia):       py sync_descontos_epi.py          → refaz desde o dia 21 de dois meses atrás
Correção 13/11/2026 (linhas repetidas da mesma SA): rodar 1 vez  py sync_descontos_epi.py --desde 20251221
"""
TABELA_ZZA = "LWHZZA010"
TABELA_SCP = "LWHSCP001"
TABELA_SRA = "LWHSRA001"

import sys
import math
import traceback
from datetime import date, datetime

try:
    import warnings
    warnings.filterwarnings("ignore", category=UserWarning)
    import pyodbc
    import pandas as pd
    from supabase import create_client
except Exception as e:
    print(f"❌ Falta biblioteca do Python: {e}")
    input("Pressione Enter para fechar...")
    sys.exit(1)

# ── CONFIGURAÇÃO (cole aqui as suas linhas, como nos outros scripts) ──────────
SERVIDOR = "XXXX"
PORTA = "1433"
BANCO = "BEQ_LWH"
USUARIO = "XXXX"
SENHA = "XXXX"
RESSUP_URL = "XXXX"
RESSUP_KEY = "XXXX"
# ─────────────────────────────────────────────────────────────────────────────


def txt(v):
    if v is None or (isinstance(v, float) and math.isnan(v)):
        return ""
    s = str(v).strip()
    return "" if s in ("nan", "None", "NaT") else s


def num(v):
    try:
        f = float(v)
        return None if math.isnan(f) or math.isinf(f) else round(f, 4)
    except Exception:
        return None


def data_iso(v):
    s = txt(v)
    if len(s) >= 10 and s[4] == "-":
        return s[:10]
    return f"{s[:4]}-{s[4:6]}-{s[6:8]}" if len(s) >= 8 and s[:8].isdigit() else None


def colunas(conn, tabela):
    df = pd.read_sql("SELECT COLUMN_NAME FROM BEQ_LWH.INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = ?", conn, params=[tabela])
    return set(c.strip().upper() for c in df["COLUMN_NAME"])


def main():
    g = globals()
    url = next((g[n] for n in ("RESSUP_URL", "SUPABASE_URL", "SB_URL", "URL") if n in g and str(g[n]) != "XXXX"), None)
    key = next((g[n] for n in ("RESSUP_KEY", "SUPABASE_KEY", "SUPABASE_SERVICE_KEY", "SERVICE_KEY", "SB_KEY", "KEY") if n in g and str(g[n]) != "XXXX"), None)
    if not url or not key:
        print("❌ Não achei o endereço/chave do Supabase. Cole suas linhas de configuração no lugar dos XXXX.")
        return
    sb = create_client(url, key)

    desde = sys.argv[sys.argv.index("--desde") + 1] if "--desde" in sys.argv else None
    if not desde:
        h = date.today()
        ano, mes = h.year, h.month - 2
        if mes <= 0:
            ano, mes = ano - 1, mes + 12
        desde = f"{ano}{mes:02d}21"
    print(f"\n🔄 Descontos de EPI desde {desde[6:8]}/{desde[4:6]}/{desde[:4]} — {datetime.now():%d/%m/%Y %H:%M}")

    conn = pyodbc.connect(f"DRIVER={{SQL Server}};SERVER={SERVIDOR},{PORTA};DATABASE={BANCO};UID={USUARIO};PWD={SENHA}")
    czza, cscp = colunas(conn, TABELA_ZZA), colunas(conn, TABELA_SCP)
    if not czza:
        print(f"❌ Não achei a tabela {TABELA_ZZA}.")
        return
    del_zza = " AND Z.D_E_L_E_T_ = ' '" if "D_E_L_E_T_" in czza else ""
    del_scp = " AND C.D_E_L_E_T_ = ' '" if "D_E_L_E_T_" in cscp else ""
    # A SA pode ter o mesmo produto em vários itens (ex.: 15 itens de 1 peça) e a ZZA gera uma linha por item, sem dizer qual
    # (as linhas vêm idênticas). Antes ficava só 1 e as outras eram descartadas. Agora: a 1ª linha da ZZA fica com o 1º item
    # do produto na SA, a 2ª com o 2º, e assim por diante (se sobrar linha, fica com os dados do 1º item e a chave leva L<n>).
    sql = f"""
SELECT RTRIM(Z.ZZA_FILIAL) filial, RTRIM(Z.ZZA_TRANS) sa, RTRIM(Z.ZZA_MATR) matricula, RTRIM(Z.ZZA_PRODUT) produto,
       RTRIM(Z.ZZA_DESC) desc_zza, RTRIM(Z.ZZA_MOTIVO) motivo, Z.ZZA_VALOR valor, RTRIM(Z.ZZA_STATUS) status,
       Z.ZZA_DATINC datinc, RTRIM(Z.ZZA_INTEG) integ, Z.ZZA_QUANT quant, Z.ZZA_VIDUTI vida, RTRIM(Z.ZZA_NOMFUN) nomfun,
       Z.ZZA_VALDES valdes, Z.SEQ seq,
       C.CP_EMISSAO emissao, RTRIM(C.CP_ITEM) item, RTRIM(C.CP_CC) cc, RTRIM(C.CP_DESCRI) descri, RTRIM(C.CP_YCOMREQ) obs, RTRIM(C.CP_SOLICIT) solic,
       R.NOME nome, RTRIM(R.CCUSTO) cc_func, RTRIM(R.DESC_CC) desc_cc, RTRIM(R.DESFUNCAO) funcao
FROM (SELECT Z0.*,
             ROW_NUMBER() OVER (PARTITION BY Z0.ZZA_FILIAL, Z0.ZZA_TRANS, Z0.ZZA_PRODUT, Z0.ZZA_MATR, Z0.ZZA_DATINC
                                ORDER BY Z0.ZZA_VALOR, Z0.ZZA_VALDES, Z0.ZZA_QUANT) AS SEQ
      FROM BEQ_LWH.dbo.{TABELA_ZZA} Z0
      WHERE Z0.ZZA_DATINC >= ?{del_zza.replace('Z.', 'Z0.')}) Z
OUTER APPLY (SELECT X.CP_EMISSAO, X.CP_ITEM, X.CP_CC, X.CP_DESCRI, X.CP_YCOMREQ, X.CP_SOLICIT, X.CP_YFILMAT
             FROM (SELECT C.CP_EMISSAO, C.CP_ITEM, C.CP_CC, C.CP_DESCRI, C.CP_YCOMREQ, C.CP_SOLICIT, C.CP_YFILMAT,
                          ROW_NUMBER() OVER (ORDER BY C.CP_ITEM) AS RN
                   FROM BEQ_LWH.dbo.{TABELA_SCP} C
                   WHERE C.CP_FILIAL = Z.ZZA_FILIAL AND C.CP_NUM = Z.ZZA_TRANS AND C.CP_PRODUTO = Z.ZZA_PRODUT{del_scp}) X
             WHERE X.RN = Z.SEQ) C1
OUTER APPLY (SELECT TOP 1 C.CP_EMISSAO, C.CP_ITEM, C.CP_CC, C.CP_DESCRI, C.CP_YCOMREQ, C.CP_SOLICIT, C.CP_YFILMAT
             FROM BEQ_LWH.dbo.{TABELA_SCP} C
             WHERE C.CP_FILIAL = Z.ZZA_FILIAL AND C.CP_NUM = Z.ZZA_TRANS AND C.CP_PRODUTO = Z.ZZA_PRODUT{del_scp}
             ORDER BY C.CP_ITEM) C0
OUTER APPLY (SELECT COALESCE(C1.CP_EMISSAO, C0.CP_EMISSAO) CP_EMISSAO, C1.CP_ITEM CP_ITEM, COALESCE(C1.CP_CC, C0.CP_CC) CP_CC,
                    COALESCE(C1.CP_DESCRI, C0.CP_DESCRI) CP_DESCRI, COALESCE(C1.CP_YCOMREQ, C0.CP_YCOMREQ) CP_YCOMREQ,
                    COALESCE(C1.CP_SOLICIT, C0.CP_SOLICIT) CP_SOLICIT, COALESCE(C1.CP_YFILMAT, C0.CP_YFILMAT) CP_YFILMAT) C
OUTER APPLY (SELECT TOP 1 R.NOME, R.CCUSTO, R.DESC_CC, R.DESFUNCAO
             FROM BEQ_LWH.dbo.{TABELA_SRA} R
             WHERE RTRIM(R.MATRICULA) = RTRIM(Z.ZZA_MATR)
             ORDER BY CASE WHEN RTRIM(R.FILIAL) = ISNULL(NULLIF(RTRIM(C.CP_YFILMAT), ''), RTRIM(Z.ZZA_FILIAL)) THEN 0 ELSE 1 END,
                      CASE WHEN R.SIT_FOLHA <> 'D' THEN 0 ELSE 1 END) R
"""
    print("  Lendo os descontos no Protheus...")
    df = pd.read_sql(sql, conn, params=[desde])
    print(f"  {len(df)} descontos lidos.")

    # Qtd Dias = dias desde a retirada anterior do mesmo produto pelo mesmo funcionário (SA anterior, CP_YMAT)
    ant = {}
    try:
        prods = sorted(set(txt(x) for x in df["produto"] if txt(x)))
        ini_hist = f"{int(desde[:4]) - 4}{desde[4:]}"
        hist = []
        for i in range(0, len(prods), 300):
            lista = ",".join("'" + p.replace("'", "") + "'" for p in prods[i:i + 300])
            q = (f"SELECT RTRIM(C.CP_YMAT) mat, RTRIM(C.CP_PRODUTO) prod, C.CP_EMISSAO emi FROM BEQ_LWH.dbo.{TABELA_SCP} C "
                 f"WHERE RTRIM(C.CP_PRODUTO) IN ({lista}) AND C.CP_EMISSAO >= '{ini_hist}' AND ISNULL(RTRIM(C.CP_YMAT),'') <> ''{del_scp}")
            hist.append(pd.read_sql(q, conn))
        h = pd.concat(hist) if hist else pd.DataFrame(columns=["mat", "prod", "emi"])
        for (m, p_), g in h.groupby(["mat", "prod"]):
            ant[(txt(m), txt(p_))] = sorted(set(txt(e) for e in g["emi"] if txt(e)))
        print(f"  Histórico de retiradas lido ({len(h)} linhas) para a Qtd Dias.")
    except Exception as e:
        print("  (não consegui calcular a Qtd Dias:", e, ")")
    conn.close()

    def qtd_dias(mat, prod, emi):
        datas = ant.get((txt(mat), txt(prod)), [])
        emi = txt(emi)[:8]
        antes = [d[:8] for d in datas if d[:8] < emi]
        if not emi or not antes:
            return None
        try:
            return (datetime.strptime(emi, "%Y%m%d") - datetime.strptime(antes[-1], "%Y%m%d")).days
        except Exception:
            return None

    regs, vistos, repetidos = [], set(), 0
    for _, r in df.iterrows():
        datinc = data_iso(r["datinc"])
        # chave = filial|SA|produto|matrícula|data + item da SA (ou nº da linha, se a SA não tiver item para ela)
        chave = "|".join([txt(r["filial"]), txt(r["sa"]), txt(r["produto"]), txt(r["matricula"]), txt(r["datinc"]),
                          txt(r["item"]) or f"L{int(float(txt(r['seq']) or 1))}"])
        if chave in vistos:
            repetidos += 1
            continue
        vistos.add(chave)
        regs.append({
            "chave": chave, "filial": txt(r["filial"]), "sa": txt(r["sa"]),
            "emissao": data_iso(r["emissao"]) or datinc, "datinc": datinc,
            "matricula": txt(r["matricula"]), "nome": txt(r["nome"]) or txt(r["nomfun"]) or None,
            "funcao": txt(r["funcao"]) or None, "cc": txt(r["cc"]) or None, "cc_func": txt(r["cc_func"]) or None,
            "desc_cc": txt(r["desc_cc"]) or None, "produto": txt(r["produto"]),
            "descricao": txt(r["descri"]) or txt(r["desc_zza"]) or None, "quantidade": num(r["quant"]),
            "motivo": txt(r["motivo"]) or None, "observacao": txt(r["obs"]) or None, "solicitante": txt(r["solic"]) or None,
            "vida_util": num(r["vida"]), "valor": num(r["valor"]), "valor_desconto": num(r["valdes"]),
            "item": txt(r["item"]) or None,
            "qtd_dias": qtd_dias(r["matricula"], r["produto"], txt(r["emissao"]) or txt(r["datinc"])),
            "status": txt(r["status"]) or None, "integrado": txt(r["integ"]) or None,
            "atualizado_em": datetime.now().isoformat(),
        })
    if repetidos:
        print(f"  ({repetidos} linhas repetidas ignoradas)")

    # refaz o período: apaga os descontos desde a data e grava de novo (as decisões ficam guardadas em outra tabela)
    print("  🗑️  Limpando o período no Supabase...")
    sb.table("descontos_epi").delete().gte("datinc", data_iso(desde)).execute()
    LOTE = 500
    for i in range(0, len(regs), LOTE):
        sb.table("descontos_epi").upsert(regs[i:i + LOTE], on_conflict="chave").execute()
        print(f"  {min(i + LOTE, len(regs))}/{len(regs)} enviados...")
    print(f"✅ {len(regs)} descontos sincronizados.\n")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"❌ Erro: {e}")
        traceback.print_exc()
    input("Pressione Enter para fechar...")
