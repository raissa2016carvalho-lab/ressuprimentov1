# -*- coding: utf-8 -*-
# upload_compras.py — dados reais direto das tabelas brutas
# Salvar em: C:\painel-protheus\upload_compras.py

import pyodbc
import pandas as pd
from datetime import datetime
from supabase import create_client

# ── CONFIGURAÇÃO ── cole aqui as mesmas linhas do seu arquivo antigo (SERVIDOR, PORTA, USUARIO, SENHA, BANCO,
#                   SUPABASE_URL e SUPABASE_KEY). Não mande essas linhas para ninguém.


sb = create_client(SUPABASE_URL, SUPABASE_KEY)
BATCH = 500

TIPO_SC_MAP = {
    "001":"REGULARIZACAO","002":"URGENCIA","003":"FUNDO FIXO",
    "004":"NORMAL","005":"RESSUPRIMENTO","006":"ESTOQUE",
    # com acento (igual Power BI)
    "REGULARIZACAO":"REGULARIZACAO","URGENCIA":"URGENCIA"
}
COND_30_SET = {
    "10 DDL","15 DDL","15,30 DD","20 DDL","21 DDL","28 DDL","30 DDL",
    "50% ANTECIPADO + 50% PARA 30DDL","50% ANTECIPADO E 50% COM 30/60 DDL",
    "50% ANTECIPADO E 50% NA ENTREGA","50% ANTECIPADO E COM 50% COM 15 DDL",
    "PAGAMENTO A VISTA","PAGAMENTO ANTECIPADO 100%"
}

def resolve_comprador(filial_str, grp_str):
    # mantém zeros à esquerda igual Power BI (ex: "01", "04", "07")
    filial = str(filial_str or "").strip().zfill(2) if str(filial_str or "").strip().isdigit() else str(filial_str or "").strip()
    grp    = str(grp_str   or "").strip()
    if filial == "37":                              return "JANAINA"
    if grp == "4010":                               return "JANAINA"
    if grp in ("2010","2011","2040","2041"):        return "JANAINA / ANDREY"
    if grp in ("1010","1020","2020","2021","2080","2092","3020","3040") and filial in ("01","04","07","1","4","7"):
                                                    return "JOAO PEDRO"
    if grp in ("1040","2060","2091","3060"):        return "ANDREY"
    if grp == "1030":                               return "AUCILANDIA"
    if grp in ("1050","2070","3080"):               return "KHAYKE"
    if grp in ("2030","2090","3070"):               return "AUCILANDIA / KHAYKE"
    if grp in ("1010","1020","2020","2021","2080","2092","3020","3040"):
                                                    return "JULIANA"
    if grp == "3010":                               return "FINANCEIRO"
    if grp in ("2050","3090"):                      return "FROTA"
    if grp == "3030":                               return "KHAYKE / JOAO PEDRO / JULIANA"
    return "NAO IDENTIFICADO"

def conectar():
    conn_str = (
        "DRIVER={SQL Server};"
        "SERVER=" + SERVIDOR + "," + PORTA + ";"
        "DATABASE=" + BANCO + ";"
        "UID=" + USUARIO + ";"
        "PWD=" + SENHA
    )
    return pyodbc.connect(conn_str)

def fmt_date(v):
    if v is None: return None
    try:
        if isinstance(v, float) and v != v: return None
        s = str(v).strip()
        if not s or s in ("NaT","None","nan",""): return None
        # formato AAAAMMDD do Protheus
        if len(s) == 8 and s.isdigit():
            return s[:4] + "-" + s[4:6] + "-" + s[6:8]
        if hasattr(v, "isoformat"): return v.isoformat()[:10]
        return s
    except: return None

def to_float(v):
    if v is None: return None
    try:
        if isinstance(v, float): return None if v != v else v
        s = str(v).strip().replace(",",".")
        # remove ponto de milhar se houver mais de um ponto
        parts = s.split(".")
        if len(parts) > 2: s = "".join(parts[:-1]) + "." + parts[-1]
        return float(s) if s else None
    except: return None

def limpar(val):
    if val is None: return None
    if isinstance(val, float) and val != val: return None
    if isinstance(val, float):
        try:
            if val == int(val): return int(val)
        except: pass
    return val

def upsert_em_lotes(tabela, registros, tamanho=500, on_conflict=None):
    enviados = 0
    for i in range(0, len(registros), tamanho):
        lote = registros[i:i+tamanho]
        q = sb.table(tabela).upsert(lote, on_conflict=on_conflict) if on_conflict else sb.table(tabela).upsert(lote)
        q.execute()
        enviados += len(lote)
        print("    " + str(enviados) + "/" + str(len(registros)))
    return enviados

# ── SYNC SCs — direto da LWHSC1010 ───────────────────────────────────────────
def sync_scs(conn):
    print("\nLendo LWHSC1010...")
    SQL_SC = """
        SELECT
            sc.C1_NUM, sc.C1_FILIAL, sc.C1_ITEM, sc.C1_PRODUTO,
            sc.C1_GRPRD, sc.C1_DESCGRP, sc.C1_DESCRI, sc.C1_UM,
            sc.C1_QUANT, sc.C1_CC, sc.C1_EMISSAO, sc.C1_OBS,
            sc.C1_SOLICIT, sc.C1_APROV, sc.C1_NOMAPRO, sc.C1_YDTAPRO,
            sc.C1_XTIPOSC, sc.STATUS_DESC, sc.CX_CC,
            p.C7_NUM   AS pedido_num,
            TRY_CAST(REPLACE(ISNULL(p.C7_PRECO,'0'),',','.') AS FLOAT) AS pedido_preco,
            TRY_CAST(REPLACE(ISNULL(p.C7_TOTAL,'0'),',','.') AS FLOAT) AS pedido_total
        FROM BEQ_LWH.dbo.LWHSC1010 sc
        LEFT JOIN BEQ_LWH.dbo.LWHSC7010 p
            ON LTRIM(RTRIM(p.C7_NUMSC))  = LTRIM(RTRIM(sc.C1_NUM))
            AND LTRIM(RTRIM(p.C7_ITEMSC)) = LTRIM(RTRIM(sc.C1_ITEM))
            AND LTRIM(RTRIM(p.C7_FILIAL)) = LTRIM(RTRIM(sc.C1_FILIAL))
        WHERE 1=1
    """
    df = pd.read_sql(SQL_SC, conn)
    print("   " + str(len(df)) + " linhas lidas (sem deletados)")

    df["C1_EMISSAO"] = df["C1_EMISSAO"].apply(fmt_date)
    df["C1_YDTAPRO"] = df["C1_YDTAPRO"].apply(fmt_date)
    df["tipo_sc"]    = df["C1_XTIPOSC"].map(TIPO_SC_MAP).fillna("")
    df["comprador"]  = df.apply(lambda r: resolve_comprador(r.get("C1_FILIAL"), r.get("C1_GRPRD")), axis=1)

    def calc_temp(r):
        try:
            if r["C1_YDTAPRO"] and r["C1_EMISSAO"]:
                return int((pd.to_datetime(r["C1_YDTAPRO"]) - pd.to_datetime(r["C1_EMISSAO"])).days)
        except: pass
        return None
    df["temp_atendimento"] = df.apply(calc_temp, axis=1)

    cols = [c for c in df.columns if c in [
        "C1_NUM","C1_ITEM","C1_FILIAL","C1_PRODUTO","C1_GRPRD","C1_DESCGRP",
        "C1_DESCRI","C1_UM","C1_QUANT","C1_CC","C1_EMISSAO","C1_OBS",
        "C1_SOLICIT","C1_APROV","C1_NOMAPRO","C1_YDTAPRO","C1_XTIPOSC",
        "STATUS_DESC","CX_CC","tipo_sc","comprador","temp_atendimento",
        "pedido_num","pedido_preco","pedido_total"
    ]]
    df = df[cols].where(pd.notnull(df[cols]), None)
    df = df.drop_duplicates(subset=["C1_NUM","C1_ITEM","C1_FILIAL"], keep="last")
    print("   " + str(len(df)) + " itens de SC unicos")

    registros = [{k: limpar(v) for k, v in r.items()} for r in df.to_dict(orient="records")]

    print("Subindo scs...")
    n = upsert_em_lotes("scs", registros, on_conflict="C1_NUM,C1_ITEM,C1_FILIAL")
    print("   OK: " + str(n) + " SCs")

# ── SYNC PEDIDOS — direto da LWHSC7010 com join LWHSC1010 ────────────────────
def sync_pedidos(conn):
    print("\nLendo PEDIDOS_SCS (view do Power BI)...")
    SQL_PED = """
        SELECT
            NUM_PEDIDO                          AS C7_NUM,
            C7_FILIAL,
            MAX(DESC_FILIAL)                    AS DESC_FILIAL,
            MAX(C7_GRPPROD)                     AS C7_GRPPROD,
            MAX(DESC_GRPPROD)                   AS DESC_GRPPROD,
            MAX(C7_COMPRADOR)                   AS C7_COMPRADOR,
            MAX(NOME_FORNECEDOR)                AS FORNECEDOR,
            MAX(C7_FORNECE)                     AS C7_FORNECE,
            MAX(COND_PAG)                       AS COND_PAG,
            MAX(EMISSAO_PEDIDO)                 AS EMISSAO_PEDIDO,
            MAX(APROVACAO_PEDIDO)               AS APROVACAO_PEDIDO,
            MAX(ENTREGA_PEDIDO)                 AS ENTREGA_PEDIDO,
            MAX(EMISSAO_NOTA)                   AS EMISSAO_NOTA,
            MAX(ENTRADA_NOTA)                   AS ENTRADA_NOTA,
            MAX(STATUS_PEDIDO)                  AS STATUS_PEDIDO,
            MAX(C7_NUMSC)                       AS C7_NUMSC,
            MAX(EMISSAO_SC)                     AS EMISSAO_SC,
            MAX(APROVACAO_SC)                   AS APROVACAO_SC,
            MAX(TIPO_SC)                        AS TIPO_SC,
            MAX(STATUS_SC)                      AS STATUS_SC,
            MAX(C7_CC)                          AS C7_CC,
            SUM(CAST(REPLACE(REPLACE(C7_TOTAL,'.',''),',','.') AS FLOAT)) AS C7_TOTAL,
            COUNT(*)                            AS QTD_ITENS
        FROM BEQ_LWH.dbo.PEDIDOS_SCS
        WHERE NUM_PEDIDO IS NOT NULL
          AND NUM_PEDIDO <> ''
        GROUP BY NUM_PEDIDO, C7_FILIAL
    """
    df = pd.read_sql(SQL_PED, conn)
    print("   " + str(len(df)) + " linhas lidas")

    # Pedidos sem grupo: o C7_GRPPROD veio vazio no Protheus. Usa o grupo do item da SC ligada ao pedido.
    SQL_GRP_SC = """
        SELECT LTRIM(RTRIM(p.C7_NUM)) AS num, LTRIM(RTRIM(p.C7_FILIAL)) AS fil,
               MAX(LTRIM(RTRIM(sc.C1_GRPRD))) AS grp, MAX(LTRIM(RTRIM(sc.C1_DESCGRP))) AS dgrp
        FROM BEQ_LWH.dbo.LWHSC7010 p
        JOIN BEQ_LWH.dbo.LWHSC1010 sc
            ON LTRIM(RTRIM(sc.C1_NUM))    = LTRIM(RTRIM(p.C7_NUMSC))
           AND LTRIM(RTRIM(sc.C1_ITEM))   = LTRIM(RTRIM(p.C7_ITEMSC))
           AND LTRIM(RTRIM(sc.C1_FILIAL)) = LTRIM(RTRIM(p.C7_FILIAL))
        WHERE ISNULL(LTRIM(RTRIM(p.C7_GRPPROD)),'') = ''
          AND ISNULL(LTRIM(RTRIM(sc.C1_GRPRD)),'') <> ''
        GROUP BY LTRIM(RTRIM(p.C7_NUM)), LTRIM(RTRIM(p.C7_FILIAL))
    """
    try:
        g = pd.read_sql(SQL_GRP_SC, conn)
        mapa = {(str(r.num).strip(), str(r.fil).strip()): (r.grp, r.dgrp) for r in g.itertuples()}
        vazio = df["C7_GRPPROD"].isna() | (df["C7_GRPPROD"].astype(str).str.strip().isin(["", "None", "nan"]))
        corrigidos = 0
        for i in df.index[vazio]:
            k = (str(df.at[i, "C7_NUM"]).strip(), str(df.at[i, "C7_FILIAL"]).strip())
            if k in mapa:
                df.at[i, "C7_GRPPROD"], df.at[i, "DESC_GRPPROD"] = mapa[k]
                corrigidos += 1
        print("   grupo preenchido pela SC em " + str(corrigidos) + " de " + str(int(vazio.sum())) + " pedidos sem grupo")
    except Exception as e:
        print("   (não consegui buscar o grupo pela SC: " + str(e) + ")")

    # datas
    for c in ["EMISSAO_PEDIDO","APROVACAO_PEDIDO","ENTREGA_PEDIDO",
              "EMISSAO_NOTA","ENTRADA_NOTA","EMISSAO_SC","APROVACAO_SC"]:
        if c in df.columns: df[c] = df[c].apply(fmt_date)

    # C7_TOTAL já vem somado do SQL como float
    if "C7_TOTAL" in df.columns:
        df["C7_TOTAL"] = df["C7_TOTAL"].apply(to_float)

    # SC
    df["C7_NUMSC"] = df["C7_NUMSC"].astype(str).str.strip().replace({"None":"","nan":"","NaT":""})
    df["SEM_SC"]   = df["C7_NUMSC"].apply(lambda v: "SEM SC" if v == "" else "COM SC")

    # tipo pedido (igual Power BI: se TIPO_SC vazio = SEM SC)
    df["TIPO_PEDIDO"] = df["TIPO_SC"].apply(
        lambda v: "SEM SC" if str(v).strip() == "" else str(v)
    )

    # cond pagamento
    df["cond_pag_30"] = df["COND_PAG"].apply(
        lambda v: None if (v is None or (isinstance(v,float) and v!=v))
        else ("<= 30 Dias" if str(v).strip().upper() in COND_30_SET else "> 30 Dias")
    )

    # comprador calculado (igual Power BI)
    df["Comp"] = df.apply(lambda r: resolve_comprador(r.get("C7_FILIAL"), r.get("C7_GRPPROD")), axis=1)

    # fornecedor
    df["FORNECEDOR"] = df["NOME_FORNECEDOR"] if "NOME_FORNECEDOR" in df.columns else df.get("C7_FORNECE","")

    # lead time: SC aprovada -> emissao pedido
    def lead(r):
        try:
            e = r.get("EMISSAO_PEDIDO"); a = r.get("APROVACAO_SC")
            if e and a: return int((pd.to_datetime(e) - pd.to_datetime(a)).days)
        except: pass
        return None
    df["leadtime_dias"] = df.apply(lead, axis=1)

    # tempo pagamento: emissao nota - emissao pedido
    def tmp_pag(r):
        try:
            ep = r.get("EMISSAO_PEDIDO"); en = r.get("EMISSAO_NOTA")
            if ep and en:
                d = int((pd.to_datetime(en) - pd.to_datetime(ep)).days)
                return d if d >= 0 else None
        except: pass
        return None
    df["tempo_pagamento"] = df.apply(tmp_pag, axis=1)

    cols = [c for c in df.columns if c in [
        "C7_NUM","C7_FILIAL","DESC_FILIAL","C7_GRPPROD","DESC_GRPPROD",
        "C7_COMPRADOR","FORNECEDOR","C7_FORNECE","COND_PAG",
        "EMISSAO_PEDIDO","APROVACAO_PEDIDO","ENTREGA_PEDIDO",
        "EMISSAO_NOTA","ENTRADA_NOTA","STATUS_PEDIDO",
        "C7_NUMSC","EMISSAO_SC","APROVACAO_SC","TIPO_SC","TIPO_PEDIDO",
        "STATUS_SC","C7_CC","C7_TOTAL","QTD_ITENS","SEM_SC",
        "cond_pag_30","Comp","leadtime_dias","tempo_pagamento"
    ]]
    df = df[cols].where(pd.notnull(df[cols]), None)
    df = df.drop_duplicates(subset=["C7_NUM","C7_FILIAL"], keep="last")
    print("   " + str(len(df)) + " pedidos unicos")

    registros = [{k: limpar(v) for k, v in r.items()} for r in df.to_dict(orient="records")]

    print("Subindo pedidos...")
    n = upsert_em_lotes("pedidos", registros, on_conflict="C7_NUM,C7_FILIAL")
    print("   OK: " + str(n) + " pedidos")

# ── SYNC PEDIDOS_GRUPO — valor por pedido × grupo, pelo status de cada ITEM ──
def sync_pedidos_grupo(conn):
    print("\nLendo LWHSC7010 (itens) para pedidos_grupo...")
    SQL = """
        SELECT
            LTRIM(RTRIM(C7_NUM))                    AS c7_num,
            LTRIM(RTRIM(C7_FILIAL))                 AS c7_filial,
            LTRIM(RTRIM(ISNULL(C7_GRPPROD,'')))     AS c7_grpprod,
            MIN(LEFT(REPLACE(C7_EMISSAO,'-',''),8)) AS emissao,
            COUNT(*)                                AS qtd_itens,
            SUM(V)                                  AS valor_total,
            SUM(CASE WHEN ST LIKE 'Rejeitado%' OR ST LIKE 'PC Elimin%' THEN 0 ELSE V END) AS valor_valido,
            SUM(CASE WHEN ST = 'Recebido' THEN V ELSE 0 END)                             AS valor_recebido,
            SUM(CASE WHEN ST = 'Recebido' OR ST LIKE 'Recebido parc%' THEN V ELSE 0 END) AS valor_rec_parc
        FROM (
            SELECT p.C7_NUM, p.C7_FILIAL,
                   -- grupo do item do pedido; se vier vazio, o grupo do item da SC ligada (só p/ os itens vazios)
                   COALESCE(NULLIF(LTRIM(RTRIM(p.C7_GRPPROD)),''), g.grp, '') AS C7_GRPPROD,
                   p.C7_EMISSAO,
                   LTRIM(RTRIM(p.STATUS_DESC)) AS ST,
                   ISNULL(TRY_CAST(REPLACE(p.C7_TOTAL,',','.') AS FLOAT), 0) AS V
            FROM BEQ_LWH.dbo.LWHSC7010 p
            LEFT JOIN (
                SELECT LTRIM(RTRIM(p2.C7_NUM)) AS n, LTRIM(RTRIM(p2.C7_ITEM)) AS it, LTRIM(RTRIM(p2.C7_FILIAL)) AS f,
                       MAX(NULLIF(LTRIM(RTRIM(s.C1_GRPRD)),'')) AS grp
                FROM BEQ_LWH.dbo.LWHSC7010 p2
                JOIN BEQ_LWH.dbo.LWHSC1010 s
                    ON LTRIM(RTRIM(s.C1_NUM))    = LTRIM(RTRIM(p2.C7_NUMSC))
                   AND LTRIM(RTRIM(s.C1_ITEM))   = LTRIM(RTRIM(p2.C7_ITEMSC))
                   AND LTRIM(RTRIM(s.C1_FILIAL)) = LTRIM(RTRIM(p2.C7_FILIAL))
                WHERE ISNULL(LTRIM(RTRIM(p2.C7_GRPPROD)),'') = ''
                GROUP BY LTRIM(RTRIM(p2.C7_NUM)), LTRIM(RTRIM(p2.C7_ITEM)), LTRIM(RTRIM(p2.C7_FILIAL))
            ) g ON g.n = LTRIM(RTRIM(p.C7_NUM)) AND g.it = LTRIM(RTRIM(p.C7_ITEM)) AND g.f = LTRIM(RTRIM(p.C7_FILIAL))
            WHERE p.C7_NUM IS NOT NULL AND LTRIM(RTRIM(p.C7_NUM)) <> ''
              AND LEFT(REPLACE(p.C7_EMISSAO,'-',''),8) >= '20250101'
        ) x
        GROUP BY LTRIM(RTRIM(C7_NUM)), LTRIM(RTRIM(C7_FILIAL)), LTRIM(RTRIM(ISNULL(C7_GRPPROD,'')))
    """
    inicio = datetime.utcnow().isoformat() + "+00:00"
    df = pd.read_sql(SQL, conn)
    print("   " + str(len(df)) + " linhas (pedido x grupo)")
    df["emissao"] = df["emissao"].apply(fmt_date)
    df["atualizado_em"] = inicio
    df = df.where(pd.notnull(df), None)
    registros = [{k: limpar(v) for k, v in r.items()} for r in df.to_dict(orient="records")]
    print("Subindo pedidos_grupo...")
    n = upsert_em_lotes("pedidos_grupo", registros, on_conflict="c7_num,c7_filial,c7_grpprod")
    # apaga combinações que não existem mais (ex.: item que mudou de grupo)
    sb.table("pedidos_grupo").delete().lt("atualizado_em", inicio).execute()
    print("   OK: " + str(n))

def sync_filiais(conn):
    print("\nLendo LWHSYS_COMPANY...")
    df = pd.read_sql(
        "SELECT LTRIM(RTRIM(M0_CODFIL)) AS filial, LTRIM(RTRIM(M0_FILIAL)) AS nome_filial "
        "FROM BEQ_LWH.dbo.LWHSYS_COMPANY WHERE D_E_L_E_T_ <> '*'", conn
    )
    df = df.drop_duplicates(subset=["filial"], keep="last")
    print("   " + str(len(df)) + " filiais")
    registros = df.to_dict(orient="records")
    sb.table("filiais").upsert(registros, on_conflict="filial").execute()
    print("   OK")

def main():
    print("=" * 50)
    print("upload_compras.py  " + datetime.now().strftime("%d/%m/%Y %H:%M:%S"))
    print("=" * 50)
    conn = conectar()
    print("Conectado ao SQL Server!")
    sync_filiais(conn)
    sync_scs(conn)
    sync_pedidos(conn)
    sync_pedidos_grupo(conn)
    conn.close()
    print("\n" + "=" * 50)
    print("Finalizado!")
    print("=" * 50)

if __name__ == "__main__":
    main()
